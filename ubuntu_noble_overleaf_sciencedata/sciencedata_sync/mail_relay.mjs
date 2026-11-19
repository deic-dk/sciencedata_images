// Overleaf's mail (invitations, password links) through ScienceData: a minimal
// SMTP server on 127.0.0.1:2525 (Overleaf's SMTP settings point here, without
// TLS or login) that hands each message to the pod owner's ScienceData server
// (user_pods api/pod-mail; the pod network's address login makes the call the
// owner's). There the sender becomes ScienceData's no-reply address, and
// recipients, size and rate are limited. No mail credentials in the pod.
// Runs as a runit service (sciencedata-mail-relay).
import net from 'node:net'
import https from 'node:https'
import http from 'node:http'

const PORT = 2525
const MAX_BYTES = 2 * 1024 * 1024 + 64 * 1024
const MAX_RCPT = 10
const API = (process.env.HOME_SERVER_PROTOCOL || 'https') + '://sciencedata/index.php/apps/user_pods/api/pod-mail'
const insecure = new https.Agent({ rejectUnauthorized: false }) // the home server's internal address

function deliver(to, message) {
  const body = JSON.stringify({ to, message: message.toString('base64') })
  const url = new URL(API)
  const lib = url.protocol === 'https:' ? https : http
  return new Promise((resolve, reject) => {
    const req = lib.request(url, {
      method: 'POST',
      agent: url.protocol === 'https:' ? insecure : undefined,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      timeout: 60000,
    }, res => {
      const chunks = []
      res.on('data', c => chunks.push(c))
      res.on('end', () => {
        let msg = ''
        try { msg = JSON.parse(Buffer.concat(chunks).toString()).message || '' } catch {}
        resolve({ status: res.statusCode, message: msg })
      })
    })
    req.on('timeout', () => req.destroy(new Error('timeout')))
    req.on('error', reject)
    req.end(body)
  })
}

net.createServer(sock => {
  let buf = Buffer.alloc(0)
  let rcpt = []
  let inData = false
  let tooBig = false
  const say = line => sock.write(line + '\r\n')
  say('220 localhost ESMTP')

  async function endData(data) {
    inData = false
    const to = rcpt
    rcpt = []
    if (tooBig) { tooBig = false; return say('552 Message too large') }
    // undo dot-stuffing
    const message = Buffer.from(data.toString('binary').replace(/^\.\./gm, '.'), 'binary')
    sock.pause() // no further input while the message is handed over
    try {
      const r = await deliver(to, message)
      if (r.status === 200) return say('250 Sent')
      console.log(`mail to ${to.join(', ')} refused (${r.status}): ${r.message}`)
      say((r.status === 429 || r.status >= 500 ? '451 ' : '554 ') + (r.message || 'Refused').replace(/[\r\n]+/g, ' '))
    } catch (e) {
      console.log(`mail to ${to.join(', ')} not delivered: ${e.message}`)
      say('451 ScienceData not reachable')
    } finally {
      sock.resume()
    }
  }

  sock.on('data', async chunk => {
    buf = Buffer.concat([buf, chunk])
    while (true) {
      if (inData) {
        const end = buf.indexOf('\r\n.\r\n')
        const start = buf.length >= 3 && buf.subarray(0, 3).toString() === '.\r\n' ? 0 : -1
        if (start === 0) { buf = buf.subarray(3); await endData(Buffer.alloc(0)); continue }
        if (end < 0) {
          if (buf.length > MAX_BYTES) { tooBig = true; buf = buf.subarray(buf.length - 4) }
          return
        }
        const data = buf.subarray(0, end + 2)
        buf = buf.subarray(end + 5)
        await endData(data)
        continue
      }
      const nl = buf.indexOf('\r\n')
      if (nl < 0) {
        if (buf.length > 4096) sock.destroy()
        return
      }
      const line = buf.subarray(0, nl).toString()
      buf = buf.subarray(nl + 2)
      const verb = line.slice(0, 4).toUpperCase()
      if (verb === 'EHLO') { say('250-localhost'); say('250 SIZE ' + MAX_BYTES) }
      else if (verb === 'HELO') say('250 localhost')
      else if (verb === 'MAIL') { rcpt = []; say('250 OK') }
      else if (verb === 'RCPT') {
        const m = line.match(/<([^<>\s]+@[^<>\s]+)>/)
        if (!m) say('501 Bad address')
        else if (rcpt.length >= MAX_RCPT) say('452 Too many recipients')
        else { rcpt.push(m[1]); say('250 OK') }
      }
      else if (verb === 'DATA') {
        if (!rcpt.length) say('503 No recipients')
        else { inData = true; say('354 End with <CRLF>.<CRLF>') }
      }
      else if (verb === 'RSET') { rcpt = []; say('250 OK') }
      else if (verb === 'NOOP') say('250 OK')
      else if (verb === 'QUIT') { say('221 Bye'); sock.end() }
      else say('502 Not implemented')
    }
  })
  sock.on('error', () => {})
}).listen(PORT, '127.0.0.1', () => console.log('mail relay on 127.0.0.1:' + PORT))
