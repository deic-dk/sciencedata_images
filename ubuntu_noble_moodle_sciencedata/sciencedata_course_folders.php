<?php
// Run by start.sh at each start (plain PHP, no Moodle needed):
//
//   echo "<the Containers app's login answer>" | php sciencedata_course_folders.php https://sciencedata
//
// In the owner's ScienceData files: the folder 'Course material' (offered in
// Moodle's file picker by repository_sciencedata), and in it a folder per
// group that logs in to this Moodle - one per course - shared read-only with
// that group, so its members find the material in ScienceData too. Only what
// is missing is made, and a group folder is shared only when it is made: the
// owner's later changes (renamed, unshared, shared differently) are left alone.
// All as the owner, through the pod network's address login.

$base = rtrim($argv[1] ?? 'https://sciencedata', '/');
$login = json_decode(stream_get_contents(STDIN), true);
$groups = is_array($login['groups'] ?? null) ? $login['groups'] : [];

function call(string $method, string $url, array $headers = [], ?string $body = null): array {
	$ch = curl_init($url);
	curl_setopt_array($ch, [
		CURLOPT_CUSTOMREQUEST => $method,
		CURLOPT_HTTPHEADER => $headers,
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_TIMEOUT => 20,
		CURLOPT_SSL_VERIFYPEER => false, // the home server's internal address
		CURLOPT_SSL_VERIFYHOST => 0,
	]);
	if ($body !== null) {
		curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
	}
	$res = curl_exec($ch);
	$status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
	curl_close($ch);
	return [$status, (string)$res];
}

/** Make a folder (path below the owner's files) unless it exists: 'exists', 'made' or '' (failed). */
function folder(string $base, string $path): string {
	$url = $base . '/files/' . implode('/', array_map('rawurlencode', explode('/', $path))) . '/';
	[$s] = call('PROPFIND', $url, ['Depth: 0']);
	if ($s === 207) {
		return 'exists';
	}
	if ($s !== 404) {
		fwrite(STDERR, "course material: '$path' not checked (HTTP $s)\n");
		return '';
	}
	[$s] = call('MKCOL', $url);
	echo "course material: made '$path' ($s)\n";
	return $s === 201 ? 'made' : '';
}

if (folder($base, 'Course material') === '') {
	exit(0);
}
$ocs = $base . '/ocs/v2.php/apps/files_sharing/api/v1/shares';
foreach ($groups as $gid) {
	$gid = (string)$gid;
	// a folder name: no slashes, no leading/trailing space or dot
	$name = trim(str_replace(['/', '\\'], '-', $gid), " .");
	if ($name === '' || folder($base, "Course material/$name") !== 'made') {
		continue; // there already (or not made): the owner's to manage
	}
	$path = "/Course material/$name";
	[$s, $json] = call('POST', $ocs . '?format=json', ['OCS-APIRequest: true'],
		http_build_query(['path' => $path, 'shareType' => 1, 'shareWith' => $gid, 'permissions' => 1]));
	$ok = $s === 200 && (int)(json_decode($json, true)['ocs']['meta']['statuscode'] ?? 0) === 200;
	echo "course material: '$path' shared read-only with group $gid" . ($ok ? '' : " - FAILED (HTTP $s)") . "\n";
}
