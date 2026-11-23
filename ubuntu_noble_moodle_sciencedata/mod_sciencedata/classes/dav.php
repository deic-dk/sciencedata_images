<?php
namespace mod_sciencedata;

/**
 * The site owner's 'Course material' folder on ScienceData, over WebDAV from
 * inside the container: the pod network's address login makes the owner's
 * files reachable at https://sciencedata/files/ without a password (the
 * certificate there names the public host, so the host name is not checked).
 * All paths are relative to one folder below 'Course material' and cannot
 * leave it.
 */
class dav {
    private string $root;

    /** @param string $folder the activity's folder, relative to 'Course material' */
    public function __construct(string $folder) {
        $dav = rtrim((string)(get_config('sciencedata', 'davurl') ?: 'https://sciencedata/files'), '/');
        $base = trim((string)(get_config('sciencedata', 'folder') ?: 'Course material'), '/');
        $path = $base . ($folder === '' ? '' : '/' . (self::clean($folder) ?? ''));
        $this->root = $dav . '/' . implode('/', array_map('rawurlencode', explode('/', $path)));
    }

    /** A path below the folder ('' = the folder itself), or null if it tries to leave it. */
    public static function clean(string $path): ?string {
        $parts = [];
        foreach (explode('/', str_replace('\\', '/', $path)) as $p) {
            if ($p === '' || $p === '.') {
                continue;
            }
            if ($p === '..' || preg_match('/[\x00-\x1f]/', $p)) {
                return null;
            }
            $parts[] = $p;
        }
        return implode('/', $parts);
    }

    /** A name for a new file or folder: no slashes, no leading dot or space. */
    public static function clean_name(string $name): string {
        $name = trim(str_replace(['/', '\\'], '-', preg_replace('/[\x00-\x1f]/', '', $name)));
        return ltrim($name, '.');
    }

    public function url(string $rel): string {
        return $this->root . ($rel === '' ? '/' : '/' . implode('/', array_map('rawurlencode', explode('/', $rel))));
    }

    private function curl(string $method, string $url, array $opts = []): \CurlHandle {
        $ch = curl_init($url);
        curl_setopt_array($ch, $opts + [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_SSL_VERIFYPEER => false, // the home server's internal address
            CURLOPT_SSL_VERIFYHOST => 0,
        ]);
        return $ch;
    }

    /** The entries of a folder: [['name', 'folder', 'size', 'mtime', 'type'], ...], or null if it is not there. */
    public function ls(string $rel): ?array {
        $body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/>'
            . '<d:getlastmodified/><d:getcontenttype/></d:prop></d:propfind>';
        $ch = $this->curl('PROPFIND', $this->url($rel), [
            CURLOPT_HTTPHEADER => ['Depth: 1', 'Content-Type: application/xml'],
            CURLOPT_POSTFIELDS => $body,
        ]);
        $xml = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($status !== 207) {
            return null;
        }
        $dom = new \DOMDocument();
        if (!@$dom->loadXML((string)$xml, LIBXML_NONET)) {
            return null;
        }
        $xp = new \DOMXPath($dom);
        $xp->registerNamespace('d', 'DAV:');
        $out = [];
        $first = true;
        foreach ($xp->query('//d:response') as $r) {
            if ($first) {
                $first = false; // the folder itself
                continue;
            }
            $name = basename(rtrim(rawurldecode((string)$xp->evaluate('string(d:href)', $r)), '/'));
            if ($name === '' || $name[0] === '.') {
                continue; // hidden files
            }
            $out[] = [
                'name' => $name,
                'folder' => $xp->query('.//d:resourcetype/d:collection', $r)->length > 0,
                'size' => (int)$xp->evaluate('string(.//d:getcontentlength)', $r),
                'mtime' => strtotime((string)$xp->evaluate('string(.//d:getlastmodified)', $r)) ?: null,
                'type' => (string)$xp->evaluate('string(.//d:getcontenttype)', $r),
            ];
        }
        // folders first, then by name
        usort($out, static fn($a, $b) => ($b['folder'] <=> $a['folder']) ?: strnatcasecmp($a['name'], $b['name']));
        return $out;
    }

    /** Upload a local file to $rel (a file path below the folder). */
    public function put(string $rel, string $localpath): bool {
        $fh = fopen($localpath, 'r');
        $ch = $this->curl('PUT', $this->url($rel), [
            CURLOPT_UPLOAD => true,
            CURLOPT_INFILE => $fh,
            CURLOPT_INFILESIZE => filesize($localpath),
            CURLOPT_TIMEOUT => 3600,
        ]);
        curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        fclose($fh);
        return $status === 201 || $status === 204;
    }

    public function mkdir(string $rel): bool {
        $ch = $this->curl('MKCOL', $this->url($rel));
        curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return $status === 201;
    }

    public function delete(string $rel): bool {
        if ($rel === '') {
            return false; // never the activity's folder itself
        }
        $ch = $this->curl('DELETE', $this->url($rel));
        curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        return $status === 204 || $status === 200;
    }

    /**
     * Send a file to the browser, streamed from ScienceData; a Range request is
     * passed on (videos can seek). Returns false if the file is not there.
     */
    public function send(string $rel, string $filename, bool $inline): bool {
        $headers = [];
        if (!empty($_SERVER['HTTP_RANGE']) && preg_match('/^bytes=[0-9,\- ]+$/', $_SERVER['HTTP_RANGE'])) {
            $headers[] = 'Range: ' . $_SERVER['HTTP_RANGE'];
        }
        $started = false;
        $ch = $this->curl('GET', $this->url($rel), [
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_TIMEOUT => 0,
            CURLOPT_HEADERFUNCTION => function ($ch, $line) use (&$started) {
                if (preg_match('/^HTTP\/\S+\s+(\d+)/', $line, $m)) {
                    $started = in_array((int)$m[1], [200, 206], true);
                    if ($started) {
                        http_response_code((int)$m[1]);
                    }
                } else if ($started && preg_match('/^(Content-Type|Content-Length|Content-Range|Accept-Ranges|Last-Modified|ETag):/i', $line)) {
                    header(trim($line));
                }
                return strlen($line);
            },
            CURLOPT_WRITEFUNCTION => function ($ch, $data) use (&$started, $filename, $inline) {
                if (!$started) {
                    return strlen($data); // an error page from the server: not sent on
                }
                if (!headers_sent()) {
                    header('Content-Disposition: ' . ($inline ? 'inline' : 'attachment')
                        . "; filename*=UTF-8''" . rawurlencode($filename));
                    header('X-Content-Type-Options: nosniff');
                    header('Cache-Control: private, max-age=0');
                }
                echo $data;
                flush();
                return strlen($data);
            },
        ]);
        curl_exec($ch);
        curl_close($ch);
        return $started;
    }
}
