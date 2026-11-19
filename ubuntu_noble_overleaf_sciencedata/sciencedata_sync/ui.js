// ScienceData sync for Overleaf - the in-page part. Inserted by the pod's nginx
// into Overleaf's pages (with the page's CSP nonce); on a project page it adds a
// "ScienceData" button for the pod's owner, opening a dialog with two one-way
// actions: import a ScienceData file or folder into the project, and export the
// project (or a part of it) to a ScienceData folder. The work is done by the
// helper behind /sciencedata/api/ (server.mjs).
(function () {
  'use strict'
  const m = location.pathname.match(/^\/project\/([0-9a-f]{24})\/?$/)
  if (!m) return
  const projectId = m[1]
  const csrf = (document.querySelector('meta[name="ol-csrfToken"]') || {}).content || ''

  const css = document.createElement('link')
  css.rel = 'stylesheet'
  css.href = '/sciencedata/ui.css'
  document.head.appendChild(css)

  const el = (tag, attrs = {}, ...kids) => {
    const e = document.createElement(tag)
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') e.className = v
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v)
      else e.setAttribute(k, v)
    }
    for (const k of kids) e.append(k)
    return e
  }

  async function api(method, url, body) {
    const r = await fetch(url, {
      method,
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', 'X-Csrf-Token': csrf },
      body: body ? JSON.stringify(body) : undefined,
    })
    const j = await r.json().catch(() => ({}))
    if (!r.ok) throw new Error(j.message || 'Error ' + r.status)
    return j
  }

  // ── a ScienceData folder browser: pick a folder (and, for import, an item) ──
  function browser(onPick, pickFiles) {
    const box = el('div', { class: 'sds-browser' })
    const state = { path: '/', selected: '' }
    const show = async p => {
      box.textContent = 'Loading…'
      try {
        const j = await api('GET', '/sciencedata/api/list?path=' + encodeURIComponent(p))
        state.path = j.path
        state.selected = pickFiles ? '' : j.path
        onPick(state.selected)
        box.textContent = ''
        const crumbs = el('div', { class: 'sds-path' }, 'ScienceData: ' + j.path)
        box.append(crumbs)
        const list = el('ul')
        if (j.path !== '/') {
          list.append(el('li', { class: 'sds-folder', onclick: () => show(j.path.replace(/\/[^/]+$/, '') || '/') }, '..'))
        }
        for (const e of j.entries) {
          const full = (j.path === '/' ? '' : j.path) + '/' + e.name
          const li = el('li', { class: e.folder ? 'sds-folder' : 'sds-file' }, e.name + (e.folder ? '/' : ''))
          if (e.folder) li.addEventListener('dblclick', () => show(full))
          li.addEventListener('click', () => {
            if (!e.folder && !pickFiles) return
            if (e.folder && !pickFiles) { show(full); return }
            list.querySelectorAll('.sds-selected').forEach(x => x.classList.remove('sds-selected'))
            li.classList.add('sds-selected')
            state.selected = full
            onPick(full)
          })
          list.append(li)
        }
        box.append(list)
        if (pickFiles) box.append(el('p', { class: 'sds-hint' }, 'Click to select a file or folder, double-click a folder to open it.'))
      } catch (e) {
        box.textContent = e.message
      }
    }
    show('/')
    return box
  }

  // ── the project's files and folders (Overleaf's own list) ──
  async function projectPaths() {
    const r = await fetch('/project/' + projectId + '/entities', { credentials: 'same-origin' })
    const j = await r.json()
    const folders = new Set(['/'])
    const files = []
    for (const e of j.entities || []) {
      files.push(e.path)
      const parts = e.path.split('/').slice(1, -1)
      for (let i = 1; i <= parts.length; i++) folders.add('/' + parts.slice(0, i).join('/'))
    }
    return { folders: [...folders].sort(), files }
  }

  function result(box, lines) {
    box.textContent = ''
    box.append(el('pre', {}, lines.join('\n')))
  }

  async function openDialog() {
    const overlay = el('div', { class: 'sds-overlay' })
    const close = () => overlay.remove()
    overlay.addEventListener('click', e => { if (e.target === overlay) close() })
    const dlg = el('div', { class: 'sds-dialog', role: 'dialog', 'aria-label': 'ScienceData' })
    overlay.append(dlg)
    document.body.append(overlay)
    dlg.append(el('div', { class: 'sds-head' }, el('h2', {}, 'ScienceData'), el('button', { class: 'sds-close', 'aria-label': 'Close', onclick: close }, '×')))

    let paths
    try { paths = await projectPaths() } catch (e) { dlg.append(el('p', {}, 'Could not read the project: ' + e.message)); return }
    const option = v => el('option', { value: v }, v)

    // Import
    const impSource = { v: '' }
    const impFolder = el('select', {}, ...paths.folders.map(option))
    const impOut = el('div', { class: 'sds-out' })
    const impBtn = el('button', { class: 'sds-primary', onclick: async () => {
      if (!impSource.v) { impOut.textContent = 'Select a file or folder in ScienceData first.'; return }
      impBtn.disabled = true
      impOut.textContent = 'Importing…'
      try {
        const j = await api('POST', '/sciencedata/api/import', { project_id: projectId, source: impSource.v, project_folder: impFolder.value })
        result(impOut, ['Imported ' + j.imported.length + ' file(s) - reload the page if the file list does not show them:', ...j.imported])
      } catch (e) { impOut.textContent = e.message }
      impBtn.disabled = false
    } }, 'Import')
    dlg.append(el('section', {},
      el('h3', {}, 'Import from ScienceData'),
      browser(v => { impSource.v = v }, true),
      el('label', {}, 'Into the project folder ', impFolder),
      el('p', { class: 'sds-hint' }, 'Files with the same name are replaced; the earlier version stays in the project history.'),
      impBtn, impOut))

    // Export
    const expTarget = { v: '/' }
    const expWhat = el('select', {}, el('option', { value: '/' }, 'The whole project'),
      ...paths.folders.filter(f => f !== '/').map(f => el('option', { value: f }, 'Folder ' + f)),
      ...paths.files.map(f => el('option', { value: f }, f)))
    const expOut = el('div', { class: 'sds-out' })
    const expBtn = el('button', { class: 'sds-primary', onclick: async () => {
      expBtn.disabled = true
      expOut.textContent = 'Exporting…'
      try {
        const j = await api('POST', '/sciencedata/api/export', { project_id: projectId, project_path: expWhat.value, target: expTarget.v })
        result(expOut, ['Wrote ' + j.written.length + ' file(s):', ...j.written])
      } catch (e) { expOut.textContent = e.message }
      expBtn.disabled = false
    } }, 'Export')
    dlg.append(el('section', {},
      el('h3', {}, 'Export to ScienceData'),
      el('label', {}, 'Export ', expWhat),
      el('p', { class: 'sds-hint' }, 'To the ScienceData folder shown below (click a folder to open it). Files with the same name are replaced; the earlier version stays in the file\'s versions in ScienceData.'),
      browser(v => { expTarget.v = v }, false),
      expBtn, expOut))
  }

  // Only for the pod's owner (the helper checks again on every call)
  fetch('/sciencedata/api/whoami', { credentials: 'same-origin' })
    .then(r => r.json())
    .then(j => {
      if (!j.owner) return
      document.body.append(el('button', { class: 'sds-launch', title: 'Import from and export to ScienceData', onclick: openDialog }, 'ScienceData'))
    })
    .catch(() => {})
})()
