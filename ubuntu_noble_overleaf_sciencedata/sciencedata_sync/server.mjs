// ScienceData sync for Overleaf: import files from the pod owner's ScienceData
// into a project, export a project's files to ScienceData.
//
// Runs as root on 127.0.0.1:8899 (runit service); nginx forwards /sciencedata/
// to it and inserts ui.js into Overleaf's pages. Root because Overleaf's own
// user may not reach the home server (firewall, see sciencedata_init.sh); the
// pod reaches its OWNER's files at https://sciencedata/files/ without a
// password. So only the owner may use it: the caller's Overleaf session (read
// from Redis) must be the user with the owner's e-mail (SD_UID), and the
// project must be theirs or shared with them. Personal pods only for now.
//
// Overleaf side: the project's tree from MongoDB (root folder id); export
// through Overleaf's own zip download (it saves open documents first), import
// through Overleaf's own upload endpoint - both with the caller's session and
// CSRF token, so Overleaf's checks and history apply.

import http from 'node:http'
import https from 'node:https'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { createRequire } from 'node:module'

const run = promisify(execFile)
const require = createRequire('/overleaf/services/web/')
const { MongoClient, ObjectId } = require('mongodb')

const PORT = 8899
const WEB = 'http://127.0.0.1:4000'
const ENVDIR = '/etc/container_environment'
const SD = (process.env.HOME_SERVER_PROTOCOL || 'https') + '://sciencedata/files'
const MAX_FILES = 2000
const MAX_FILE_BYTES = 50 * 1024 * 1024 // Overleaf's upload limit

const env = name => {
  try { return fs.readFileSync(path.join(ENVDIR, name), 'utf8').trim() } catch { return process.env[name] || '' }
}
const OWNER = env('SD_UID')
const mongo = new MongoClient(env('OVERLEAF_MONGO_URL') || 'mongodb://127.0.0.1:27017/sharelatex')
const db = () => mongo.db()

// ── who is calling ────────────────────────────────────────────────────────────

function cookie(req, name) {
  for (const part of (req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=')
    if (i > 0 && part.slice(0, i).trim() === name) return decodeURIComponent(part.slice(i + 1).trim())
  }
  return ''
}

/** The Overleaf user of the request's session, or null. */
async function sessionUser(req) {
  const raw = cookie(req, env('COOKIE_NAME') || 'overleaf.sid') // "s:<sid>.<signature>"
  const m = raw.match(/^s:([^.]+)\./)
  if (!m) return null
  const { stdout } = await run('redis-cli', ['-h', '127.0.0.1', '--raw', 'GET', 'sess:' + m[1]])
  if (!stdout.trim()) return null
  try {
    const sess = JSON.parse(stdout)
    const u = sess.user || (sess.passport && sess.passport.user)
    return u && u._id ? { id: String(u._id), email: String(u.email || '') } : null
  } catch { return null }
}

/** The owner, with access to the project (write access for $write). */
async function authorize(req, projectId, write) {
  const user = await sessionUser(req)
  if (!user) throw httpError(401, 'Not logged in to Overleaf.')
  if (!OWNER || user.email.toLowerCase() !== OWNER.toLowerCase()) {
    throw httpError(403, 'Only the owner of this container can reach their ScienceData from it.')
  }
  if (projectId === undefined) return { user }
  if (!/^[0-9a-f]{24}$/.test(projectId)) throw httpError(400, 'Invalid project.')
  const p = await db().collection('projects').findOne({ _id: new ObjectId(projectId) },
    { projection: { owner_ref: 1, collaberator_refs: 1, readOnly_refs: 1, reviewer_refs: 1, rootFolder: 1 } })
  if (!p) throw httpError(404, 'No such project.')
  const has = list => (list || []).some(x => String(x) === user.id)
  const canWrite = String(p.owner_ref) === user.id || has(p.collaberator_refs)
  if (write ? !canWrite : !(canWrite || has(p.readOnly_refs) || has(p.reviewer_refs))) {
    throw httpError(403, 'You do not have access to this project.')
  }
  return { user, project: p }
}

// ── ScienceData (WebDAV, as the pod's owner) ─────────────────────────────────

const insecure = new https.Agent({ rejectUnauthorized: false }) // the home server's internal address

function dav(method, sdPath, { body, headers = {}, stream } = {}) {
  const url = new URL(SD + encodePath(sdPath))
  const lib = url.protocol === 'https:' ? https : http
  return new Promise((resolve, reject) => {
    const req = lib.request(url, { method, headers, agent: url.protocol === 'https:' ? insecure : undefined }, res => {
      if (stream) return resolve(res)
      const chunks = []
      res.on('data', c => chunks.push(c))
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }))
    })
    req.on('error', reject)
    req.setTimeout(600000, () => req.destroy(new Error('ScienceData did not answer')))
    if (body && typeof body.pipe === 'function') body.pipe(req)
    else req.end(body)
  })
}

const encodePath = p => '/' + cleanPath(p).split('/').filter(Boolean).map(encodeURIComponent).join('/')
function cleanPath(p) {
  const parts = []
  for (const s of String(p || '').split('/')) {
    if (s === '' || s === '.') continue
    if (s === '..') throw httpError(400, 'Invalid path.')
    parts.push(s)
  }
  return '/' + parts.join('/')
}

/** The entries of a ScienceData folder: [{name, folder, size}]. */
async function sdList(sdPath) {
  const r = await dav('PROPFIND', sdPath, {
    headers: { Depth: '1', 'Content-Type': 'application/xml' },
    body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>',
  })
  if (r.status === 404) throw httpError(404, 'No such folder in ScienceData: ' + sdPath)
  if (r.status !== 207) throw httpError(502, 'ScienceData answered ' + r.status)
  const xml = r.body.toString('utf8')
  const self = encodePath(sdPath).replace(/\/$/, '')
  const out = []
  for (const resp of xml.split(/<d:response>/i).slice(1)) {
    const href = decodeURIComponent((resp.match(/<d:href>([^<]*)<\/d:href>/i) || [])[1] || '')
    const rel = href.replace(/^.*?\/files/, '').replace(/\/$/, '')
    if (rel === decodeURIComponent(self) || rel === '') continue
    out.push({
      name: rel.split('/').pop(),
      folder: /<d:collection\s*\/>/i.test(resp),
      size: Number((resp.match(/<d:getcontentlength>(\d+)<\/d:getcontentlength>/i) || [])[1] || 0),
    })
  }
  return out.sort((a, b) => (b.folder - a.folder) || a.name.localeCompare(b.name))
}

/** All files below a ScienceData path (a file: just itself), relative to its parent. */
async function sdFiles(sdPath) {
  sdPath = cleanPath(sdPath)
  const parent = path.posix.dirname(sdPath)
  const r = await dav('PROPFIND', sdPath, { headers: { Depth: '0' } })
  if (r.status === 404) throw httpError(404, 'Not found in ScienceData: ' + sdPath)
  const isFolder = /<d:collection\s*\/>/i.test(r.body.toString('utf8'))
  if (!isFolder) return [path.posix.relative(parent, sdPath)]
  const files = []
  const walk = async dir => {
    for (const e of await sdList(dir)) {
      const p = path.posix.join(dir, e.name)
      if (e.folder) await walk(p)
      else files.push(path.posix.relative(parent, p))
      if (files.length > MAX_FILES) throw httpError(413, 'More than ' + MAX_FILES + ' files.')
    }
  }
  await walk(sdPath)
  return files
}

async function sdMkdirs(dir) {
  let cur = ''
  for (const s of cleanPath(dir).split('/').filter(Boolean)) {
    cur += '/' + s
    const r = await dav('MKCOL', cur)
    if (![201, 405].includes(r.status)) throw httpError(502, 'Could not create ' + cur + ' in ScienceData (' + r.status + ')')
  }
}

// ── Overleaf (as the caller, through Overleaf's own endpoints) ───────────────

const forward = req => ({ cookie: req.headers.cookie || '', 'x-csrf-token': req.headers['x-csrf-token'] || '' })

/** Export: project files (all, or below projectPath) to a ScienceData folder. */
async function exportProject(req, { project_id: pid, project_path: projectPath = '/', target }) {
  await authorize(req, pid, false)
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sd-export-'))
  try {
    const zip = await fetch(`${WEB}/Project/${pid}/download/zip`, { headers: forward(req) })
    if (!zip.ok) throw httpError(502, 'Overleaf could not make the zip (' + zip.status + ')')
    fs.writeFileSync(path.join(tmp, 'p.zip'), Buffer.from(await zip.arrayBuffer()))
    await run('unzip', ['-q', '-o', path.join(tmp, 'p.zip'), '-d', path.join(tmp, 'p')])
    const base = path.join(tmp, 'p', cleanPath(projectPath))
    if (!fs.existsSync(base)) throw httpError(404, 'Not in the project: ' + projectPath)
    const files = []
    const walk = d => {
      for (const n of fs.readdirSync(d)) {
        const f = path.join(d, n)
        if (fs.statSync(f).isDirectory()) walk(f)
        else files.push(f)
      }
    }
    fs.statSync(base).isDirectory() ? walk(base) : files.push(base)
    // A folder or file keeps its name in the target (as import does); the
    // whole project goes into the target folder itself
    const root = cleanPath(projectPath) === '/' ? base : path.dirname(base)
    target = cleanPath(target)
    await sdMkdirs(target)
    const done = []
    for (const f of files) {
      const rel = path.relative(root, f).split(path.sep).join('/')
      const dest = path.posix.join(target, rel)
      await sdMkdirs(path.posix.dirname(dest))
      const r = await dav('PUT', dest, { body: fs.createReadStream(f), headers: { 'Content-Length': fs.statSync(f).size } })
      if (![200, 201, 204].includes(r.status)) throw httpError(502, 'Could not write ' + dest + ' (' + r.status + ')')
      done.push(dest)
    }
    return { written: done }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
}

/** Import: a ScienceData file or folder into a project folder. */
async function importToProject(req, { project_id: pid, source, project_folder: projectFolder = '/' }) {
  const { project } = await authorize(req, pid, true)
  const rootId = String(project.rootFolder && project.rootFolder[0] && project.rootFolder[0]._id)
  source = cleanPath(source)
  const files = await sdFiles(source)
  const parent = path.posix.dirname(source)
  const done = []
  for (const rel of files) {
    const res = await dav('GET', path.posix.join(parent, rel), { stream: true })
    if (res.statusCode !== 200) throw httpError(502, 'Could not read ' + rel + ' from ScienceData (' + res.statusCode + ')')
    const chunks = []
    let size = 0
    for await (const c of res) {
      size += c.length
      if (size > MAX_FILE_BYTES) { res.destroy(); throw httpError(413, rel + ' is larger than Overleaf accepts (50 MB).') }
      chunks.push(c)
    }
    const target = path.posix.join(cleanPath(projectFolder), rel).replace(/^\//, '')
    const form = new FormData()
    form.append('name', path.posix.basename(target))
    form.append('relativePath', target)
    form.append('qqfile', new Blob([Buffer.concat(chunks)]), path.posix.basename(target))
    const up = await fetch(`${WEB}/Project/${pid}/upload?folder_id=${rootId}`, { method: 'POST', headers: forward(req), body: form })
    const answer = await up.json().catch(() => ({}))
    if (!up.ok || answer.success === false) {
      throw httpError(502, 'Overleaf refused ' + target + ': ' + (answer.error || up.status) + (done.length ? ' (' + done.length + ' file(s) imported before)' : ''))
    }
    done.push('/' + target)
  }
  return { imported: done }
}

// ── HTTP ─────────────────────────────────────────────────────────────────────

function httpError(status, message) { return Object.assign(new Error(message), { status }) }

async function readJson(req) {
  const chunks = []
  for await (const c of req) chunks.push(c)
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}') } catch { throw httpError(400, 'Invalid request.') }
}

const STATIC = {
  '/sciencedata/ui.js': ['ui.js', 'application/javascript; charset=utf-8'],
  '/sciencedata/ui.css': ['ui.css', 'text/css; charset=utf-8'],
}

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost')
  const send = (status, obj) => {
    res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' })
    res.end(JSON.stringify(obj))
  }
  try {
    if (STATIC[url.pathname]) {
      const [file, type] = STATIC[url.pathname]
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' })
      return res.end(fs.readFileSync(new URL(file, import.meta.url)))
    }
    if (req.method === 'GET' && url.pathname === '/sciencedata/api/whoami') {
      const user = await sessionUser(req)
      return send(200, { owner: !!(user && OWNER && user.email.toLowerCase() === OWNER.toLowerCase()) })
    }
    if (req.method === 'GET' && url.pathname === '/sciencedata/api/list') {
      await authorize(req)
      return send(200, { path: cleanPath(url.searchParams.get('path')), entries: await sdList(url.searchParams.get('path') || '/') })
    }
    if (req.method === 'POST' && url.pathname === '/sciencedata/api/export') {
      return send(200, await exportProject(req, await readJson(req)))
    }
    if (req.method === 'POST' && url.pathname === '/sciencedata/api/import') {
      return send(200, await importToProject(req, await readJson(req)))
    }
    send(404, { message: 'Not found' })
  } catch (e) {
    if (!e.status) console.error('sciencedata-sync:', e)
    send(e.status || 500, { message: e.status ? e.message : 'Something went wrong: ' + e.message })
  }
}).listen(PORT, '127.0.0.1', () => console.log('sciencedata-sync listening on 127.0.0.1:' + PORT))
