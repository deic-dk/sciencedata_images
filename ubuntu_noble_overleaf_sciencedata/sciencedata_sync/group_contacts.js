// Group pods (sciencedata-contacts service): every account is a member of the
// pod's ScienceData group, so each is made a contact of every other one - the
// Share dialog then suggests them as you type. Added as n:0 (never shared
// with), so people actually collaborated with stay first; existing entries are
// left alone. Overleaf's suggestions show at most 50 contacts.
const users = db.users.find({ holdingAccount: { $ne: true } }, { _id: 1 }).toArray().map(u => u._id)
let added = 0
if (users.length > 1) {
	for (const u of users) {
		const known = (db.contacts.findOne({ user_id: u }) || {}).contacts || {}
		const set = {}
		for (const v of users) {
			const k = v.toString()
			if (k !== u.toString() && !known[k]) set['contacts.' + k] = { n: 0, ts: new Date(0) }
		}
		if (Object.keys(set).length) {
			db.contacts.updateOne({ user_id: u }, { $set: set }, { upsert: true })
			added += Object.keys(set).length
		}
	}
}
if (added) print('ScienceData: ' + added + ' contact(s) added between group members')
