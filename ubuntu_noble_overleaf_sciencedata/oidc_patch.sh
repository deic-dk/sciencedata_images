#!/bin/sh
# Build time: ScienceData logins (OpenID Connect) are matched to Overleaf
# accounts by the ScienceData user ID only - never by e-mail.
#
# The extended CE's OIDC module (OIDCAuthenticationManager.findOrCreateUser),
# when no account carries the login's ID, takes ANY account with the login's
# e-mail and links it - even one linked to another ScienceData user. Nextcloud
# users can set their own e-mail address, so a group member could take over
# the owner's (administrator) account. Here a login whose e-mail belongs to an
# account without that ID is refused with a message (an error: the module
# shows its text; its "not allowed" path would send the user to sign up).
# The owner's own account (made before ScienceData login, e.g. restored from a
# personal pod) gets the ID recorded at start (sciencedata_admin.sh).
# Fails the build if the code no longer has the expected shape.
set -e
F=/overleaf/services/web/modules/authentication/oidc/app/src/OIDCAuthenticationManager.mjs
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "      user = await User.findOne({ 'email': email }).exec()\n      if (!user) {"
new = ("      // ScienceData (oidc_patch.sh): never link by e-mail - an account with this\n"
       "      // e-mail but without this login's ID is someone else's\n"
       "      if (await User.findOne({ 'email': email }).exec()) {\n"
       "        throw new Error('The ScienceData account ' + oidcUserId + ' cannot log in here: its e-mail address (' + email + ') already belongs to another account in this Overleaf. (To log in with another ScienceData account, log out of ScienceData first.)')\n"
       "      }\n"
       "      user = null\n"
       "      if (!user) {")
assert s.count(old) == 1, "oidc_patch: expected code not found in " + p
open(p, "w").write(s.replace(old, new, 1))
PY
grep -q "oidc_patch.sh" "$F"
echo "oidc_patch: OIDC logins are matched by ID only"
