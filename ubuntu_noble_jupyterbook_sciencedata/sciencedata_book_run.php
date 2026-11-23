<?php
// After each build (sciencedata_book.sh): the "Run on ScienceData" button.
//
//   php sciencedata_book_run.php <site dir> <meta dir>
//
// A notebook page gets the button only if the book's folder - or a folder
// above it - has a public link: the run page of the server holding the link
// copies the notebook from it into the reader's own files and opens it in
// their notebook server. The link is the owner's choice; nothing is shared
// here. Looked up through the pod network's address login (the owner's
// sharing API); the server's public address - the button's target - comes from
// the Containers app (pod-login: home_url), as the pod only knows the internal one. Writes <meta>/run.json and adds the button's script to the
// built pages; without a link, run.json says so and the pages stay as built.

$site = rtrim($argv[1] ?? '/var/lib/book/site', '/');
$meta = rtrim($argv[2] ?? '/var/lib/book/meta', '/');
$env = parse_ini_file('/etc/sciencedata_book.env') ?: [];
$base = ($env['HOME_SERVER_PROTOCOL'] ?? 'https') . '://sciencedata';

// the mounted folder, relative to the owner's files: /tank/data/<dir>/<owner>/files/<path>
$volume = (string)($env['NFS_VOLUME_PATH'] ?? '');
$rel = preg_match('#^/tank/data/[^/]+/[^/]+/files/(.*)$#', $volume, $m) ? trim($m[1], '/') : null;

function get(string $url, array $headers = []): ?array {
	$ch = curl_init($url);
	curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 20, CURLOPT_HTTPHEADER => $headers,
		CURLOPT_SSL_VERIFYPEER => false, CURLOPT_SSL_VERIFYHOST => 0]); // the home server's internal address
	$res = curl_exec($ch);
	curl_close($ch);
	$j = json_decode((string)$res, true);
	return is_array($j) ? $j : null;
}

function shares(string $base, string $path): array {
	$data = get($base . '/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json&path=' . rawurlencode($path),
		['OCS-APIRequest: true'])['ocs']['data'] ?? [];
	return is_array($data) ? $data : [];
}

// the home server's public address (test/override: SD_HOME_URL)
$home = rtrim((string)(getenv('SD_HOME_URL') ?: (get($base . '/index.php/apps/user_pods/api/pod-login')['home_url'] ?? '')), '/');

$run = null;
if ($rel !== null && $home !== '' && !empty($env['HOME_SERVER'])) {
	// the folder itself or the nearest folder above it with a public link
	$parts = $rel === '' ? [] : explode('/', $rel);
	for ($i = count($parts); $i >= 0 && $run === null; $i--) {
		$dir = '/' . implode('/', array_slice($parts, 0, $i));
		foreach (shares($base, $dir) as $s) {
			if ((int)($s['share_type'] ?? -1) === 3 && !empty($s['token']) && empty($s['password'])) {
				$within = implode('/', array_slice($parts, $i)); // the book's folder inside the shared one
				$run = ['run' => $home . '/index.php/apps/user_pods/run', 'token' => $s['token'],
					'prefix' => $within === '' ? '/' : '/' . $within . '/'];
				break;
			}
		}
	}
}
file_put_contents("$meta/run.json", json_encode($run ?? ['run' => null]));
if ($run === null) {
	echo "Run on ScienceData: off - make a public link to the book's folder (Share -> share link) to get the button on notebook pages\n";
	exit(0);
}
// the script in every page (once)
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($site, FilesystemIterator::SKIP_DOTS));
$n = 0;
foreach ($it as $f) {
	if (substr($f->getFilename(), -5) !== '.html') {
		continue;
	}
	$html = file_get_contents($f->getPathname());
	if (strpos($html, '/_sciencedata/run.js') === false && stripos($html, '</head>') !== false) {
		$html = preg_replace('#</head>#i', '<script src="/_sciencedata/run.js" defer></script></head>', $html, 1);
		file_put_contents($f->getPathname(), $html);
		$n++;
	}
}
echo "Run on ScienceData: on ($n pages, through the public link of " . ($run['prefix'] === '/' ? 'the book folder' : 'a folder above it') . ")\n";
