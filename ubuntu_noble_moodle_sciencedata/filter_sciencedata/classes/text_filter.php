<?php
namespace filter_sciencedata;

/**
 * Links to ScienceData public shares (https://<host>/s/<token>, also
 * /index.php/s/<token> and their /download forms) in course text become:
 *
 *  - a notebook (.ipynb): a rendered preview (ScienceData's nbviewer) with a
 *    "Run this notebook" button - the share's own server copies it into the
 *    student's ScienceData files and opens it in their notebook server - and
 *    a download link;
 *  - a video: a player, streaming from the share (seeking works);
 *  - a folder: a small card with its name and size and a link to it.
 *
 * Other links stay as they are. What a link points to is asked once from the
 * share's public WebDAV (PROPFIND, no login) and cached for an hour.
 */
class text_filter extends \core_filters\text_filter {
    #[\Override]
    public function filter($text, array $options = []) {
        if (!is_string($text) || stripos($text, '/s/') === false) {
            return $text;
        }
        $hosts = preg_split('/[\s,]+/', strtolower(trim((string)get_config('filter_sciencedata', 'hosts'))), -1, PREG_SPLIT_NO_EMPTY);
        if (!$hosts) {
            return $text;
        }
        $hostre = implode('|', array_map(static fn($h) => preg_quote($h, '#'), $hosts));
        $re = '#<a\s[^>]*?href=(["\'])(https://(?:' . $hostre . ')(?::\d+)?)/(?:index\.php/)?s/([A-Za-z0-9]{6,64})'
            . '(?:/download(?:/[^"\'?\#]*)?)?/?\1[^>]*>.*?</a>#is';
        $out = preg_replace_callback($re, function (array $m): string {
            $html = $this->render(strtolower($m[2]), $m[3]);
            return $html ?? $m[0];
        }, $text);
        return $out ?? $text; // a regex failure leaves the text as it was
    }

    /** The rich form of a share link, or null to leave the link as it is. */
    private function render(string $base, string $token): ?string {
        $info = $this->share_info($base, $token);
        if ($info === null) {
            return null;
        }
        $name = $info['name'] !== '' ? $info['name'] : $token;
        $file = $base . '/public.php/dav/files/' . $token;
        $page = $base . '/s/' . $token;

        if (!$info['folder'] && (preg_match('/\.ipynb$/i', $name) || $info['type'] === 'application/x-ipynb+json')) {
            // nbviewer renders only addresses ending in .ipynb: the share's download address with the file name
            $nbviewer = rtrim((string)get_config('filter_sciencedata', 'nbviewer'), '/');
            $source = substr($base, strlen('https://')) . '/s/' . $token . '/download/' . rawurlencode($name);
            $run = rtrim((string)get_config('filter_sciencedata', 'runurl'), '/') ?: $base;
            $out = '<div class="filter-sciencedata filter-sciencedata-notebook">';
            if ($nbviewer !== '') {
                $out .= '<iframe src="' . s($nbviewer . '/urls/' . $source) . '" title="'
                    . s(get_string('notebookpreview', 'filter_sciencedata', $name)) . '" loading="lazy"'
                    . ' sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox"'
                    . ' style="width:100%;height:32rem;border:1px solid #dee2e6;border-radius:.375rem"></iframe>';
            }
            $out .= '<div style="margin:.5rem 0 1rem">'
                . '<a class="btn btn-primary" target="_blank" rel="noopener" href="'
                . s($run . '/index.php/apps/user_pods/run?token=' . rawurlencode($token)) . '">'
                . get_string('runnotebook', 'filter_sciencedata') . '</a> '
                . '<a class="btn btn-secondary" href="' . s($file) . '" download="' . s($name) . '">'
                . get_string('download', 'filter_sciencedata') . '</a> '
                . '<span class="text-muted">' . s($name) . '</span></div></div>';
            return $out;
        }
        if (!$info['folder'] && str_starts_with($info['type'], 'video/')) {
            return '<div class="filter-sciencedata filter-sciencedata-video">'
                . '<video controls preload="metadata" style="max-width:100%;max-height:70vh" src="' . s($file) . '">'
                . '<a href="' . s($page) . '">' . s($name) . '</a></video></div>';
        }
        if ($info['folder']) {
            $size = $info['size'] !== null ? ' &middot; ' . display_size($info['size']) : '';
            return '<span class="filter-sciencedata filter-sciencedata-folder"'
                . ' style="display:inline-block;padding:.5rem .75rem;margin:.25rem 0;border:1px solid #dee2e6;border-radius:.375rem">'
                . '<strong>' . s($name) . '</strong> <span class="text-muted">&middot; '
                . get_string('folder', 'filter_sciencedata') . $size . '</span> '
                . '<a target="_blank" rel="noopener" href="' . s($page) . '">'
                . get_string('openfolder', 'filter_sciencedata') . '</a></span>';
        }
        return null;
    }

    /**
     * What the share points to - ['name', 'folder', 'type', 'size'] - from its
     * public WebDAV, cached; null when unknown (no such share, or the server not
     * reachable - the link then stays a plain link).
     */
    private function share_info(string $base, string $token): ?array {
        $cache = \cache::make('filter_sciencedata', 'shares');
        $key = sha1($base . '/' . $token);
        $hit = $cache->get($key);
        if ($hit !== false) {
            return $hit['info'];
        }
        $body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:prop>'
            . '<d:displayname/><d:resourcetype/><d:getcontenttype/><d:getcontentlength/><oc:size/></d:prop></d:propfind>';
        $ch = curl_init($base . '/public.php/dav/files/' . $token);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST => 'PROPFIND',
            CURLOPT_POSTFIELDS => $body,
            CURLOPT_HTTPHEADER => ['Depth: 0', 'Content-Type: application/xml'],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_TIMEOUT => 5,
        ]);
        $xml = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($xml === false || $status === 0 || $status >= 500) {
            return null; // not reachable: ask again next time
        }
        $info = null;
        if ($status === 207) {
            $dom = new \DOMDocument();
            if (@$dom->loadXML((string)$xml, LIBXML_NONET)) {
                $xp = new \DOMXPath($dom);
                $xp->registerNamespace('d', 'DAV:');
                $xp->registerNamespace('oc', 'http://owncloud.org/ns');
                $folder = $xp->query('//d:resourcetype/d:collection')->length > 0;
                $size = trim((string)$xp->evaluate('string(//oc:size)'));
                if ($size === '') {
                    $size = trim((string)$xp->evaluate('string(//d:getcontentlength)'));
                }
                $info = [
                    'name' => trim((string)$xp->evaluate('string(//d:displayname)')),
                    'folder' => $folder,
                    'type' => strtolower(trim((string)$xp->evaluate('string(//d:getcontenttype)'))),
                    'size' => is_numeric($size) ? (int)$size : null,
                ];
            }
        }
        $cache->set($key, ['info' => $info]); // also "not a share" (404 etc.), for the hour
        return $info;
    }
}
