#!/bin/sh
# Build time: ScienceData logins (OAuth 2 / OpenID Connect) are matched to
# Moodle accounts by the ScienceData user ID only - never by e-mail.
#
# Moodle's OAuth 2 login, when no account is linked to the login's ID and the
# issuer requires no confirmation, links ANY account with the login's e-mail
# address. Nextcloud users can set their own e-mail address, so a ScienceData
# user could take over e.g. the administrator's account. Here such a login is
# refused with a message. (Requiring confirmation instead would make every new
# member confirm by mail.) The owner's link to the admin account is made at
# start (sciencedata_oidc.php). Fails the build if the code no longer has the
# expected shape.
set -e
F=/var/www/moodle/public/auth/oauth2/classes/auth.php
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """                } else {
                    \\auth_oauth2\\api::link_login($userinfo, $issuer, $moodleuser->id, true);
                    // We dont have profile loaded on $moodleuser, so load it.
                    require_once($CFG->dirroot.'/user/profile/lib.php');
                    profile_load_custom_fields($moodleuser);
                    $userinfo = $this->update_user($userinfo, $moodleuser);
                    // No redirect, we will complete this login.
                }
"""
new = """                } else {
                    // ScienceData (oauth2_patch.sh): never link a login to an account by its
                    // e-mail address - an account with this address but without this login's
                    // ID is someone else's.
                    $event = \\core\\event\\user_login_failed::create(['other' => ['username' => $userinfo['username'],
                                                                                'reason' => AUTH_LOGIN_UNAUTHORISED]]);
                    $event->trigger();
                    $SESSION->loginerrormsg = 'The account ' . s($userinfo['username']) . ' cannot log in here: its e-mail'
                        . ' address already belongs to another account on this site.';
                    $client->log_out();
                    redirect(new moodle_url('/login/index.php'));
                }
"""
assert s.count(old) == 1, "oauth2_patch: expected code not found in " + p
open(p, "w").write(s.replace(old, new, 1))
PY
grep -q "oauth2_patch.sh" "$F"
php -l "$F" >/dev/null
echo "oauth2_patch: OAuth 2 logins are matched by ID only"
