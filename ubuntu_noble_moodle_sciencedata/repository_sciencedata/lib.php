<?php
// The pod owner's course-material folder on ScienceData in Moodle's file
// picker - an ordinary ScienceData folder (web interface, sync client, shared
// with the course's group for the students), read from inside the container
// over WebDAV: the pod network's address login makes the owner's files
// (https://sciencedata/files/) readable without a password - the certificate
// there names the public host, so the host name is not checked, as for the
// pod's other calls to its home server. Files are added to courses as copies, or as references that
// Moodle refreshes from ScienceData (at most every five minutes, downloading
// only when the file has changed).
defined('MOODLE_INTERNAL') || die();

require_once($CFG->dirroot . '/repository/lib.php');

class repository_sciencedata extends repository {
    /** How long a reference is trusted before ScienceData is asked again (s). */
    const LIFETIME = 300;

    /** Files being synchronised: asking a stored file for its size, hash or date synchronises it again. */
    private static array $syncing = [];

    public static function get_type_option_names() {
        return ['pluginname', 'folder', 'davurl'];
    }

    public static function type_config_form($mform, $classname = 'repository') {
        parent::type_config_form($mform, $classname);
        $mform->addElement('text', 'folder', get_string('folder', 'repository_sciencedata'));
        $mform->setType('folder', PARAM_RAW_TRIMMED);
        $mform->addHelpButton('folder', 'folder', 'repository_sciencedata');
        $mform->addElement('text', 'davurl', get_string('davurl', 'repository_sciencedata'));
        $mform->setType('davurl', PARAM_URL);
        $mform->addHelpButton('davurl', 'davurl', 'repository_sciencedata');
    }

    public function check_login() {
        return true;
    }

    public function global_search() {
        return false;
    }

    public function supported_returntypes() {
        return FILE_INTERNAL | FILE_REFERENCE;
    }

    /** The folder's address, e.g. https://sciencedata/files/Course%20material */
    private function base(): string {
        $dav = rtrim((string)(get_config('sciencedata', 'davurl') ?: 'https://sciencedata/files'), '/');
        $folder = trim((string)(get_config('sciencedata', 'folder') ?: 'Course material'), '/');
        return $dav . '/' . implode('/', array_map('rawurlencode', explode('/', $folder)));
    }

    /** A path below the folder, '' for the folder itself; null if it tries to leave it. */
    private static function clean(string $path): ?string {
        $parts = [];
        foreach (explode('/', $path) as $p) {
            if ($p === '' || $p === '.') {
                continue;
            }
            if ($p === '..' || str_contains($p, "\0")) {
                return null;
            }
            $parts[] = $p;
        }
        return implode('/', $parts);
    }

    private function url(string $rel): string {
        return $this->base() . ($rel === '' ? '/' : '/' . implode('/', array_map('rawurlencode', explode('/', $rel))));
    }

    /** One WebDAV request (plain curl: Moodle's curl class refuses the internal address). */
    private function request(string $method, string $url, array $headers = [], ?string $body = null, ?string $saveas = null): array {
        $ch = curl_init($url);
        $out = $saveas !== null ? fopen($saveas, 'w') : null;
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT => $saveas !== null ? 600 : 20,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_SSL_VERIFYPEER => false, // the home server's internal address
            CURLOPT_SSL_VERIFYHOST => 0,
        ]);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        }
        if ($out) {
            curl_setopt($ch, CURLOPT_FILE, $out);
        } else {
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        }
        $res = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($out) {
            fclose($out);
        }
        return [$status, $out ? '' : (string)$res];
    }

    /** PROPFIND: [[name, rel, folder?, size, mtime, etag], ...] - the entry itself first. */
    private function propfind(string $rel, int $depth): ?array {
        $body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/>'
            . '<d:getcontentlength/><d:getlastmodified/><d:getetag/></d:prop></d:propfind>';
        [$status, $xml] = $this->request('PROPFIND', $this->url($rel),
            ['Depth: ' . $depth, 'Content-Type: application/xml'], $body);
        if ($status !== 207) {
            return null;
        }
        $dom = new DOMDocument();
        if (!@$dom->loadXML($xml, LIBXML_NONET)) {
            return null;
        }
        $xp = new DOMXPath($dom);
        $xp->registerNamespace('d', 'DAV:');
        $entries = [];
        foreach ($xp->query('//d:response') as $r) {
            $href = rtrim(rawurldecode((string)$xp->evaluate('string(d:href)', $r)), '/');
            $name = basename($href);
            $entries[] = [
                'name' => $name,
                'folder' => $xp->query('.//d:resourcetype/d:collection', $r)->length > 0,
                'size' => (int)$xp->evaluate('string(.//d:getcontentlength)', $r),
                'mtime' => strtotime((string)$xp->evaluate('string(.//d:getlastmodified)', $r)) ?: null,
                'etag' => trim((string)$xp->evaluate('string(.//d:getetag)', $r), '"'),
            ];
        }
        return $entries;
    }

    public function get_listing($path = '', $page = '') {
        global $OUTPUT;
        $folder = trim((string)(get_config('sciencedata', 'folder') ?: 'Course material'), '/');
        $ret = ['dynload' => true, 'nosearch' => true, 'nologin' => true, 'list' => [],
            'path' => [['name' => $folder, 'path' => '']]];
        $rel = self::clean((string)$path);
        if ($rel === null) {
            return $ret;
        }
        $acc = '';
        foreach ($rel === '' ? [] : explode('/', $rel) as $p) {
            $acc = ltrim($acc . '/' . $p, '/');
            $ret['path'][] = ['name' => $p, 'path' => $acc];
        }
        $entries = $this->propfind($rel, 1);
        if ($entries === null) {
            $ret['list'] = [];
            $ret['message'] = get_string('notfound', 'repository_sciencedata', $folder);
            return $ret;
        }
        array_shift($entries); // the folder itself
        $dirs = [];
        $files = [];
        foreach ($entries as $e) {
            if ($e['name'] === '' || $e['name'][0] === '.') {
                continue; // hidden files
            }
            $child = ltrim($rel . '/' . $e['name'], '/');
            if ($e['folder']) {
                $dirs[] = ['title' => $e['name'], 'path' => $child, 'children' => [], 'datemodified' => $e['mtime'],
                    'thumbnail' => $OUTPUT->image_url(file_folder_icon())->out(false)];
            } else {
                $files[] = ['title' => $e['name'], 'source' => $child, 'size' => $e['size'], 'datemodified' => $e['mtime'],
                    'thumbnail' => $OUTPUT->image_url(file_extension_icon($e['name']))->out(false)];
            }
        }
        $sort = static fn($a, $b) => strnatcasecmp($a['title'], $b['title']);
        usort($dirs, $sort);
        usort($files, $sort);
        $ret['list'] = array_merge($dirs, $files);
        return $ret;
    }

    public function get_file($source, $saveas = '') {
        $rel = self::clean((string)$source);
        if ($rel === null || $rel === '') {
            throw new repository_exception('cannotdownload', 'repository');
        }
        $path = $this->prepare_file($saveas);
        [$status] = $this->request('GET', $this->url($rel), [], null, $path);
        if ($status !== 200) {
            throw new repository_exception('cannotdownload', 'repository');
        }
        return ['path' => $path];
    }

    public function get_file_reference($source) {
        return (string)self::clean((string)$source);
    }

    public function get_file_source_info($source) {
        $folder = trim((string)(get_config('sciencedata', 'folder') ?: 'Course material'), '/');
        return 'ScienceData: ' . $folder . '/' . $source;
    }

    public function get_reference_details($reference, $filestatus = 0) {
        $details = $this->get_file_source_info($reference);
        return $filestatus ? get_string('lostsource', 'repository', $details) : $details;
    }

    public function get_reference_file_lifetime($ref) {
        return self::LIFETIME;
    }

    /** Refresh a reference: ask ScienceData; download only when the file changed. */
    public function sync_reference(stored_file $file) {
        if ($file->get_referencelastsync() + self::LIFETIME > time() || isset(self::$syncing[$file->get_id()])) {
            return false;
        }
        self::$syncing[$file->get_id()] = true;
        try {
            return $this->sync_now($file);
        } finally {
            unset(self::$syncing[$file->get_id()]);
        }
    }

    private function sync_now(stored_file $file): bool {
        $rel = self::clean((string)$file->get_reference());
        $entries = $rel ? $this->propfind($rel, 0) : null;
        if ($entries === null || !$entries || $entries[0]['folder']) {
            $file->set_missingsource();
            return true;
        }
        $remote = $entries[0];
        // unchanged since the last download: keep the content, note the check
        if ($remote['mtime'] && (int)$file->get_timemodified() === (int)$remote['mtime']
                && (int)$file->get_filesize() === $remote['size'] && $file->get_filesize() > 0) {
            $file->set_synchronized($file->get_contenthash(), $file->get_filesize(), 0, $remote['mtime']);
            return true;
        }
        try {
            $info = $this->get_file($rel);
        } catch (Exception $e) {
            return false; // keep what we have; try again later
        }
        $file->set_synchronised_content_from_file($info['path']);
        $file->set_synchronized(sha1_file($info['path']), filesize($info['path']), 0, $remote['mtime'] ?: null);
        @unlink($info['path']);
        return true;
    }

    public function send_file($storedfile, $lifetime = null, $filter = 0, $forcedownload = false, ?array $options = null) {
        $this->import_external_file_contents($storedfile);
        $options = is_array($options) ? $options : [];
        $options['sendcachedexternalfile'] = true;
        \core\session\manager::write_close();
        send_stored_file($storedfile, $lifetime, $filter, $forcedownload, $options);
    }

    public function contains_private_data() {
        return false;
    }
}
