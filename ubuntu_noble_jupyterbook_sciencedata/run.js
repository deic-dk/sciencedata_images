// "Run on ScienceData" on pages made from a notebook (.ipynb): opens the
// notebook in the reader's own notebook server on ScienceData - their own copy,
// through the run page of the server holding the book folder's public link.
(function () {
	'use strict'
	fetch('/_sciencedata/run.json').then(function (r) { return r.json() }).then(function (cfg) {
		if (!cfg || !cfg.run || !cfg.token) return
		// the page's source, as the theme's "download source" link names it: _sources/<path>.ipynb
		var src = document.querySelector('a[href*="_sources/"][href$=".ipynb"]')
		if (!src) return
		var path = decodeURIComponent(new URL(src.getAttribute('href'), location.href).pathname.replace(/^.*\/_sources\//, ''))
		var href = cfg.run + '?token=' + encodeURIComponent(cfg.token) + '&path=' + encodeURIComponent(cfg.prefix + path)
		var a = document.createElement('a')
		a.href = href
		a.target = '_blank'
		a.rel = 'noopener'
		a.textContent = 'Run on ScienceData'
		a.title = 'Open this notebook in your own notebook server on ScienceData'
		a.className = 'btn btn-sm sciencedata-run'
		a.style.cssText = 'font-size:.85rem;margin-left:.5rem;border:1px solid currentColor;border-radius:.35rem;padding:.15rem .6rem;white-space:nowrap'
		var bar = document.querySelector('.article-header-buttons')
		if (bar) {
			bar.insertBefore(a, bar.firstChild)
		} else {
			a.style.cssText += ';position:fixed;right:1rem;bottom:1rem;z-index:1000;background:#00679e;color:#fff;border-color:#00679e'
			document.body.appendChild(a)
		}
	}).catch(function () {})
})()
