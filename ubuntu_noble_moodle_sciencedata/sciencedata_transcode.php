<?php
// Run by cron every 5 minutes as www (one run at a time - flock in the cron
// line); plain PHP plus ffmpeg, no Moodle needed:
//
//   php sciencedata_transcode.php https://sciencedata/files
//
// Videos in 'Course material' in the owner's ScienceData files that browsers
// cannot play as they are (other formats, other codecs, too large, not
// streamable) get a web version: MP4, H.264 + AAC, at most 720 lines,
// streamable from the start - in a hidden '.web' folder next to the original,
// named '<original name>.mp4'. The ScienceData folder activity plays it. A web
// version older than its original is made again; one whose original is gone is
// removed. Read and written over WebDAV through the pod network's address login.
// At most one video per run, so a long lecture does not hold up the rest for
// longer than it takes; the next run continues.

const VIDEO = '/\.(mp4|m4v|mov|mkv|webm|avi|wmv|mpe?g|flv|3gp|ts|mts|m2ts|ogv)$/i';
const STATE = '/var/moodledata/.sciencedata_transcode.json'; // originals found web-ready or failed, by etag

$dav = rtrim($argv[1] ?? 'https://sciencedata/files', '/') . '/' . rawurlencode('Course material');
$state = json_decode((string)@file_get_contents(STATE), true) ?: [];

function req(string $method, string $url, array $headers = [], $body = null, ?string $saveas = null): array {
	$ch = curl_init($url);
	$out = $saveas !== null ? fopen($saveas, 'w') : null;
	$opts = [CURLOPT_CUSTOMREQUEST => $method, CURLOPT_HTTPHEADER => $headers, CURLOPT_CONNECTTIMEOUT => 5,
		CURLOPT_TIMEOUT => 7200, CURLOPT_SSL_VERIFYPEER => false, CURLOPT_SSL_VERIFYHOST => 0]; // the home server's internal address
	if (is_resource($body)) {
		$opts += [CURLOPT_UPLOAD => true, CURLOPT_INFILE => $body, CURLOPT_INFILESIZE => fstat($body)['size']];
	} else if ($body !== null) {
		$opts[CURLOPT_POSTFIELDS] = $body;
	}
	$opts += $out ? [CURLOPT_FILE => $out] : [CURLOPT_RETURNTRANSFER => true];
	curl_setopt_array($ch, $opts);
	$res = curl_exec($ch);
	$status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
	curl_close($ch);
	if ($out) {
		fclose($out);
	}
	return [$status, $out ? '' : (string)$res];
}

function url(string $base, string $rel): string {
	return $base . ($rel === '' ? '/' : '/' . implode('/', array_map('rawurlencode', explode('/', $rel))));
}

/** A folder's entries (hidden ones too): name => [folder, size, mtime, etag]; null if not there. */
function ls(string $base, string $rel): ?array {
	$body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/>'
		. '<d:getlastmodified/><d:getetag/></d:prop></d:propfind>';
	[$s, $xml] = req('PROPFIND', url($base, $rel) . ($rel === '' ? '' : '/'), ['Depth: 1', 'Content-Type: application/xml'], $body);
	if ($s !== 207) {
		return null;
	}
	$dom = new DOMDocument();
	if (!@$dom->loadXML($xml, LIBXML_NONET)) {
		return null;
	}
	$xp = new DOMXPath($dom);
	$xp->registerNamespace('d', 'DAV:');
	$out = [];
	$first = true;
	foreach ($xp->query('//d:response') as $r) {
		if ($first) {
			$first = false;
			continue;
		}
		$name = basename(rtrim(rawurldecode((string)$xp->evaluate('string(d:href)', $r)), '/'));
		$out[$name] = [
			'folder' => $xp->query('.//d:resourcetype/d:collection', $r)->length > 0,
			'size' => (int)$xp->evaluate('string(.//d:getcontentlength)', $r),
			'mtime' => strtotime((string)$xp->evaluate('string(.//d:getlastmodified)', $r)) ?: 0,
			'etag' => trim((string)$xp->evaluate('string(.//d:getetag)', $r), '"'),
		];
	}
	return $out;
}

/** Is the video playable in browsers as it is (MP4/WebM, H.264/VP8/VP9/AV1, AAC/Opus/Vorbis, <= 1080 lines)? */
function webready(string $url, string $name): bool {
	if (!preg_match('/\.(mp4|m4v|webm)$/i', $name)) {
		return false;
	}
	$cmd = 'ffprobe -v error -tls_verify 0 -show_entries stream=codec_type,codec_name,height -show_entries format=format_name -of json '
		. escapeshellarg($url);
	$j = json_decode((string)shell_exec($cmd), true);
	if (!is_array($j) || empty($j['streams'])) {
		return false;
	}
	foreach ($j['streams'] as $st) {
		if (($st['codec_type'] ?? '') === 'video' && (!in_array($st['codec_name'] ?? '', ['h264', 'vp8', 'vp9', 'av1'], true)
				|| (int)($st['height'] ?? 0) > 1080)) {
			return false;
		}
		if (($st['codec_type'] ?? '') === 'audio' && !in_array($st['codec_name'] ?? '', ['aac', 'mp3', 'opus', 'vorbis'], true)) {
			return false;
		}
	}
	return true;
}

/** Find the first video needing a web version (and tidy web versions whose original is gone). */
function find(string $base, string $rel, array &$state, int $depth = 0): ?array {
	if ($depth > 8) {
		return null;
	}
	$entries = ls($base, $rel);
	if ($entries === null) {
		return null;
	}
	$web = ltrim($rel . '/.web', '/');
	$webs = isset($entries['.web']) ? (ls($base, $web) ?? []) : [];
	foreach ($webs as $w => $info) {
		$orig = preg_replace('/\.mp4$/', '', $w);
		if (!$info['folder'] && !isset($entries[$orig])) {
			req('DELETE', url($base, "$web/$w"));
			echo "removed the web version of '" . ltrim("$rel/$orig", '/') . "' (original gone)\n";
		}
	}
	foreach ($entries as $name => $e) {
		if ($name === '' || $name[0] === '.' || $e['folder'] || !preg_match(VIDEO, $name)) {
			continue;
		}
		$path = ltrim("$rel/$name", '/');
		$w = $webs["$name.mp4"] ?? null;
		if ($w && $w['mtime'] >= $e['mtime']) {
			continue; // web version up to date
		}
		$key = $path . "\0" . $e['etag'];
		if (isset($state[$key])) {
			continue; // found web-ready, or failed, as it is now
		}
		if (webready(url($base, $path), $name)) {
			$state[$key] = 'ready';
			continue;
		}
		return ['rel' => $rel, 'name' => $name, 'key' => $key];
	}
	foreach ($entries as $name => $e) {
		if ($e['folder'] && $name !== '' && $name[0] !== '.') {
			if ($hit = find($base, ltrim("$rel/$name", '/'), $state, $depth + 1)) {
				return $hit;
			}
		}
	}
	return null;
}

$job = find($dav, '', $state);
if ($job) {
	$src = url($dav, ltrim($job['rel'] . '/' . $job['name'], '/'));
	$tmp = tempnam('/var/cache/moodle/temp', 'sdweb') . '.mp4';
	$cmd = 'nice -n 19 ffmpeg -nostdin -v error -y -tls_verify 0 -i ' . escapeshellarg($src)
		. ' -map 0:v:0 -map 0:a:0? -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p'
		. " -vf 'scale=-2:min(720\\,ih)' -c:a aac -b:a 128k -ac 2 -movflags +faststart " . escapeshellarg($tmp) . ' 2>&1';
	$t0 = time();
	$err = shell_exec($cmd);
	$path = ltrim($job['rel'] . '/' . $job['name'], '/');
	if (is_file($tmp) && filesize($tmp) > 0) {
		$web = ltrim($job['rel'] . '/.web', '/');
		req('MKCOL', url($dav, $web));
		$fh = fopen($tmp, 'r');
		[$s] = req('PUT', url($dav, $web . '/' . $job['name'] . '.mp4'), [], $fh);
		fclose($fh);
		echo "web version of '$path': " . (in_array($s, [201, 204], true) ? 'made' : "not stored (HTTP $s)") . ' in ' . (time() - $t0) . " s\n";
	} else {
		$state[$job['key']] = 'failed';
		echo "web version of '$path' failed: " . trim(substr((string)$err, 0, 300)) . "\n";
	}
	@unlink($tmp);
	@unlink(preg_replace('/\.mp4$/', '', $tmp));
}
@file_put_contents(STATE, json_encode($state)); // no data root (e.g. a read-only mount): probed again next time
