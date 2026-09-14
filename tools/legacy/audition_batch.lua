-- Auditions every line Henry can actually be made to say, ten at a time.
--
--     python tools/dev_console.py --file tools/audition_batch.lua
--
-- Set BATCH to the group of ten to hear. Each line is fired five seconds after
-- the last, and logged as it goes out with the words to expect, so the log is a
-- transcript of what should have been heard and in what order.
--
-- Why a batch rather than one line per run: auditioning one at a time costs a
-- round trip each, and the rider said plainly that going back and forth through
-- lists was the waste. Ten in a row at a listening pace is one round trip for
-- ten answers.
--
-- The list is every alias surviving the four usability filters in
-- `tools/henry_impact_lines.py` -- always-true entry condition, repeatable
-- rather than once-per-playthrough, shipped audio recorded by Henry's actor
-- alone, and printed in full so the whole set is judged and not its first
-- member. Ordered shortest first, since a collision wants few words.
--
-- Nothing here touches the mod's own pools. It only speaks.

local BATCH = 2
local SPACING_MS = 5000
local PER_BATCH = 10

local LINES = {
	{ "q_returnToSkalitz_deadPeople", "Jesus..." },
	{ "q_woundedSoul_fixingLeg4", "Done." },
	{ "q_libri_prohibiti_henry_aquiredNecronomicon1", "That's it!" },
	{ "q_returnToSkalitz_deadHangman", "Oh, God." },
	{ "q_rides_traitor_henry_trail_skirt", "Shameless hussy!" },
	{ "revelation_murderer_ohfuck", "Oh fuck!" },
	{ "q_auschitz_player_falseLead_3", "Hmmm, nothing here. / A bed. / Nothing interesting here. / Nothing unusual." },
	{ "q_infiltration_vranikFound", "That could be it." },
	{ "revelation_murderer_smell", "Jesus, something stinks here!" },
	{ "q_execExec_swordBarkWithAdvice", "And now to blunt it!" },
	{ "q_night_rescue_alarmHenry", "Fuck, the alarm's been sounded!" },
	{ "q_rides_traitor_henry_trail_shirt", "It started getting interesting here." },
	{ "q_counterfeiters_crimeScene_area", "Good God, what a bloody mess." },
	{ "q_counterfeiters_player_findHiddenMercury", "Hmm... vessels with quicksilver in them." },
	{ "q_escapeToTalmberk_player_warnOthers", "Run for it! / Go! They'll kill you all! / Ru... run for it! / Flee! / Warn the others! They've torched Skalitz! / Flee! To Talmberg!" },
	{ "q_istvans_reinforcements_henryAttack", "Grind those whoresons into the dirt! / At them! Chaaaarge!" },
	{ "q_massacre_deadPeasasnt", "How could anyone be so cruel?" },
	{ "q_massacre_footprintNearFence", "Tracks! Someone fled to the north!" },
	{ "q_returnToSkalitz_deadCollier", "Sweet Jesus, it's the charcoal burner..." },
	{ "q_rides_bacchus_ringIsStolenFromHenry", "Shit, where's that damned ring? / Someone must have pinched it! / And what the fuck is this?" },
	{ "q_waldensians_henryFoundMeetingPlace", "Hmm... It seems I've found it." },
	{ "q_waldensians_henryListen", "I could try listening from here." },
	{ "q_counterfeiters_player_rapotaFreeze", "Fuck! Stop! Stop right there! Hear me?" },
	{ "q_execExec_barkNeedPoison", "First I have to get some poison." },
	{ "q_massacre_footprint", "They went deeper and deeper, for sure!" },
	{ "revelation_murderer_shield", "A shield of Sir Radzig's garrison... strange..." },
	{ "revelation_murderer_trigger_caveBody4", "Jesus Christ, he was only a boy." },
	{ "q_dlc_revelation_johankasGravePrayer", "Johanka... / Amen. / Forgive me for not doing more for you. / I'll miss your courage and your selflessness. / May God have mercy on you." },
	{ "q_massacre_blood1", "So much blood! It leads to the pond." },
	{ "q_returnToSkalitz_zbysekRunsAway", "That's right, turn tail and run, you bastard!" },
	{ "q_rides_traitor_henry_trail_blanket", "Romance on the rocky outcrop, so it seems." },
	{ "q_rides_traitor_henry_trail_flask", "Seems it's not booze we're interested in anymore." },
	{ "q_rides_traitor_henry_trail_scarf", "Looks like Hansel and Gretel went this way." },
	{ "q_rides_traitor_henry_trail_wreath", "It's always nice to take away a memento." },
	{ "q_superstition_eggsFresh", "I can't throw these eggs in there yet. / I don't have any rotten eggs. / These eggs aren't rotten. / These don't stink enough." },
	{ "revelation_breadcrumbBark4", "A stony channel... let's see where that leads." },
	{ "q_cemetery_flowers_leaveBark", "First I'd better finish what I came here for." },
	{ "q_counterfeiters_crimeScene_brokenWheel", "This one won't be going anywhere any time soon." },
	{ "q_counterfeiters_crimeScene_sack", "It looks like that wagon was loaded with charcoal." },
	{ "q_counterfeiters_player_iShouldLootUlrich", "I should search him - I may find something." },
	{ "q_escapeToTalmberk_wrongWay_leftOfRiver", "Left! Talmberg is to the left along the stream!" },
	{ "q_execExec_barkNeedPoisonWithoutAdvice", "Hmm... I'm still missing something. Maybe Hermann will know." },
	{ "q_pribyslav_player_burnArrows", "Well you won't be shooting these arrows... / The fewer arrows you have, the better for us. / I'd like to see you try shooting these now." },
	{ "q_returnToSkalitz_butcher_stolenGoods", "My God, I'm no better than that bastard Zbyshek." },
	{ "q_superstition_meatNotSpoiled", "This isn't spoiled enough. / This meat is too fresh. / It needs more time to get good and rotten. / Not spoiled enough. / This meat doesn't look spoiled." },
	{ "q_waldensians_henryCantListen", "I can't do it now. They know about me." },
	{ "player_examineInjuredWorker", "He's still breathing but he probably won't wake up again." },
	{ "q_auschitz_player_kubasMoney", "Quite a pile of money. Where did he get that?" },
	{ "q_cemetery_flowers_ladasgrave", "This must be it. May she rest in peace, Lord." },
	{ "q_counterfeiters_crimeScene_colliers", "Hmm ... charcoal-burners. Someone must have seen or heard something." },
	{ "q_counterfeiters_crimeScene_pathEvidence", "Another clue - I must be going the right way. / It looks like blood. / Blood. / I'm on the right track. / This way!" },
	{ "q_massacre_deadHorse", "They really did slaughter them. Why would anyone do that?" },
	{ "q_raubritter_playerBloodTrack", "Blood. This is the right way. / Another trace. They dragged him this way. / That looks like blood. / He was bleeding plenty! Should be easy to track him. / This is the way. / Looks like this is the right way. / More blood. Must be close." },
	{ "q_searchForSaint_lastChanceToKill", "Fuck! If I don't kill Pious now, I never will." },
	{ "q_superstition_burryLedecko", "May you join your wife and child. Rest in peace." },
	{ "revelation_barkNearMineEntrance", "Ah! There's an entrance up there. Could that be it?" },
	{ "revelation_murderer_trigger_caveBody3", "Looks like a Cuman, judging by the caftan. Poetic justice!" },
	{ "q_counterfeiters_crimeScene_deadBody", "Hmm ... the body's still warm, the attackers can't be far." },
	{ "q_execExec_oilBarkDone", "There we go! He won't be lighting anything with this soup!" },
	{ "q_execExec_swordBarkDone", "There. He couldn't chop the head off a chicken with this!" },
	{ "q_execExec_swordBarkReturn", "There we go! Now to get it back to the executioner." },
	{ "q_infiltrationAndCapture_afterGate", "That was easy. Now I'd better take a look around here." },
	{ "q_libri_prohibiti_henry_shouldBeLeaving", "And now to get away quickly before anyone catches me here." },
	{ "q_night_rescue_savingPtacek", "Fuck! I'll have to carry him out of here, right now!" },
	{ "q_returnToSkalitz_gravePlace", "This is a good place. You're going to like it here." },
	{ "q_stone_matusFricekDead", "Well, I knew all along how that pair would end up." },
	{ "q_superstition_burryRattay", "Now you're in hallowed ground, maybe you'll finally have some rest." },
	{ "revelation_murderer_trigger_caveBody5", "Poor wretch. What did he do to deserve such a fate?" },
	{ "q_escapeToTalmberk_player_wrongWay", "Shit! This is the wrong way! / Damn it! Not this way! Where the hell have I gone now?! / No, not this way! Jesus! / I'm finished! Serves me right for not paying attention!" },
	{ "q_execExec_swordBarkWithoutAdvice", "Hmm. What to do with the sword now? Maybe Hermann will know." },
	{ "q_massacre_aboutBayonet", "Why, it's a hoofpick. Someone in Neuhof must know more about it." },
	{ "q_returnToSkalitz_blankasRing", "I'll take this as a keepsake to remember you by, my dearest." },
	{ "q_searchForSaint_aboutAntoninDagger", "What do we have here? / A nice sharp dagger. Now what would a monk need that for?" },
	{ "q_waldensians_henryPickedUpCross", "A cross, nicely carved. Hmm... someone in the village might recognise it." },
	{ "q_execExec_ropeBarkDone", "That should do it. It'll never hold the weight of a grown man." },
	{ "q_execExec_toolsBarkDone", "If he tries to torture anyone with this, the lucky fellow'll die quickly." },
	{ "q_execExec_troughBarkDone", "There! They won't be pulling anything for a few days. Except long faces!" },
	{ "q_pribyslav_player_sawCuman", "What are the Cumans doing here? Looks like there's more to the story." },
	{ "revelation_breadcrumbBark3", "The pond in the middle... Johanka mentioned some stony watercourse... / There was a stream here that supplied those ponds. It must be nearby..." },
	{ "revelation_murderer_trigger_caveBody1", "Maybe a merchant who took a shortcut this way to avoid paying customs. / He looks like he was well-heeled... Judging from what's left of him." },
	{ "revelation_murderer_trigger_caveBody6", "A Skalitz waffenrock! Maybe Sir Radzig sent someone here to check on things. / That didn't turn out too well." },
	{ "q_capCum_treasureTrailPlayer", "Stop looking around and hurry up. I haven't got all day. / Hurry up, Cuman. / I'm starting to get nervous. Get a move on! / I'd advise you to look faster. I didn't come here for a nice stroll." },
	{ "q_escapeToTalmberk_player_somebodysBed", "This bed is probably taken. I'm supposed to go and sleep in the chamber." },
	{ "q_returnToSkalitz_deadGerman_fecalVersion", "And all I did was throw manure. I'm sorry, Deutsch - please forgive me." },
	{ "q_returnToSkalitz_deadWomen", "Why would anyone do this? What did these poor souls ever do to them?" },
	{ "q_samopesh_player_punishedPeta", "This man took part in the massacre at Neuhof! And he was punished lawfully!" },
	{ "revelation_commentDecorations", "I can't wait to hear what Johanka thinks of this. / Good heavens, what's all this?! Candles, pictures - someone's made quite a shrine here." },
	{ "player_gotRingFromChest", "What?! This is nothing but an ordinary copper band. It's not worth a tin penny." },
	{ "q_dlc_revelation_matejsGravePrayer", "I'll miss you, my friend... / Amen. / At least you'll be reunited with your loved ones... May your soul rest in peace. / And this is how you end up. / You fought bravely in Merhojed and saved a lot of people. / The Lord has taken you to himself." },
	{ "q_returnToSkalitz_deadBailiff", "The Bailiff... He didn't run like me. He died with a sword in his hand." },
	{ "q_superstition_tooFewMeat", "That's not going to be enough. / I'll have to get more of that meat. The butcher will notice if there's less. / That's not enough meat. / I don't have enough meat yet. / I need more of that meat." },
	{ "revelation_breadcrumbBark1", "Castle behind me... the footbridge to the pools... this looks like the place Johanka described. / What was it she said...? I should go to the waterworks?" },
	{ "revelation_murderer_lootBark", "God have mercy, this is a small fortune! Fine clothing, armour and weapons. Serious loot! / And a Cuman faceplate helmet. Interesting." },
	{ "q_counterfeiters_colliers_stolenBag", "Traces of blood. Hmm ... And these are the same sacks that were by that wagon." },
	{ "q_massacre_deadSmil", "Smil, the stud farm owner. I saw him in Skalitz a few times. His poor widow." },
	{ "q_superstition_badMeat", "But this is a different kind of meat. / This isn't the right kind of meat. / I can't put this there. The butcher will know right away it's not the same meat. / Hmm, no good. It has to be the same kind of meat." },
	{ "q_counterfeiters_crimeScene_chest", "This is valuable. They must have been in a hurry, or they'd never have left it behind." },
	{ "q_counterfeiters_henry_ulrichBackInPub", "Damn. Well, I suppose it doesn't matter as long as he goes back to the Sasau inn." },
	{ "q_enteringTheMonastery_placeAllItems", "Strange feeling being without all of that. I didn't realise how much I'd grown used to it." },
	{ "q_massacre_goToCourtyardFaild", "I hope Bernard won't be too angry. / Damn it, they really didn't wait for me! Now I've got to get to Neuhof by myself." },
	{ "q_returnToSkalitz_accessDenied", "I've got business to take care of here first. / God, how I wish to be gone from this place, but first I must bury my parents." },
	{ "devilplay_afterAttack_henryBark", "I'll never be able to explain this to anyone. That fucking ointment. Damn that old hag! Now what? / What the fuck happened here? Shit! / Oh my God! These are no demons, just flesh and blood woodcutters." },
	{ "q_counterfeiters_crimeScene_blood", "Someone was wounded here. It looks like another person dragged him off. Maybe there'll be some tracks ..." },
	{ "q_massacre_corpseAtPond", "Poor wretch, he must have crawled here. / If it was the horses they were after, there'll be even more of them by the main stables." },
	{ "q_massacre_deadHorseAtStable", "Such senseless brutality! They slaughtered horses as well as people and yet it seems they didn't take anything." },
	{ "revelation_breadcrumbBark2", "This is where they wash the ore... According to what Johanka said, I should go uphill somewhere here..." },
	{ "revelation_murderer_horseBark", "No doubt he wanted to raise the alarm about the raid on Skalitz, but those bastards got him. / Christ, poor wretch!" },
	{ "q_auschitz_player_kubasSword", "A sword? What the hell does an Uzhitz crofter need a weapon for? And where did he get it?" },
	{ "q_counterfeiters_zachsCopper", "Hmm ... copper, and quite a lot of it. I wonder what Zach will have to say about this." },
	{ "q_millerDate_dVisitTereza_again", "I wonder what Theresa's doing now. I could stop by and see her again. I enjoyed it last time." },
	{ "q_visitInBaths_rosesBark", "What was it she said? Sage, something, something else and... and roses? What would a bouquet be without roses! / There's some in the Upper Castle garden..." },
	{ "revelation_breadcrumbBark5", "This is it? I thought it was supposed to be a big cave? Well, maybe it's bigger on the inside." },
	{ "q_millerDate_dVisitTereza", "I wonder what Theresa's up to? I haven't seen her for a long time. Maybe I could go and see her..." },
	{ "q_auschitz_player_pain", "Lord above, they did a hell of a job on him. It must have been agony. How come no one heard anything?" },
	{ "q_returnToSkalitz_shovelTaken", "You poor thing - they killed your master, didn't they? I know how you feel. I lost... I lost my family too." },
	{ "q_auschitz_player_kubasArmor", "Armour? Well, it seems Lubosh wasn't your everyday crofter. And judging by the bloodstains, it looks like he lived the way he died." },
	{ "q_escapeToTalmberk_wrongWay_skaliceMill", "To the right is the road to the mines, a dead end. That's no use - I have to go straight for Talmberg!" },
	{ "q_samopesh_player_hintFallback", "Hmm, that didn't quite go as planned. Now all I can do is search the woods and try to stumble on their camp by chance." },
	{ "q_cemetery_flowers_aloishome", "Everything burned to the ground. So where can I find something that belonged to the dead? I'll take some of these pieces of charred wood. That should do." },
	{ "q_returnToSkalitz_deadBlanka", "No, no, no... why?  Not you... It wasn't supposed to be you... Bianca... I'll find the bastards that did this to you... I'll find them, I swear it! / Just wait a moment. I'll take care of my parents and then I'll come back for you. I won't leave you like this." },
	{ "q_returnToSkalitz_deadGerman", "You stood by his side and he did this to you... And in the end you were a hero. You didn't run away, didn't abandon them... like me..." },
	{ "q_counteroffensive_henryToHimself", "I need to set off as soon as possible to give the Talmbergers the message, or they won't arrive in time to help us at Vranik. / I have to go and see Sir Divish right away, otherwise they won't get to Vranik in time. / If I don't set off right now to deliver the message to Sir Divish, there's a good chance our men will lose the battle. I can't let that happen." },
	{ "q_auschitz_player_head", "What's this? It looks like someone hit him very hard on the head. Could they have bludgeoned him to death and THEN gutted him? That would explain why he didn't scream." },
	{ "q_auschitz_player_readSign", "'JUDAS'. Hmm, it looks like this is meant to be a warning. But for who? And why? Maybe the gang had a falling out. But a bandit who knows how to write isn't something you see every day. / An inscription in blood. It's a pity I don't know how to read. It looks like they wanted to give someone a warning, but who? And a bandit who knows how to write isn't something you see every day." },
}

local m = HorseCollisionMod

if not m then
	System.LogAlways("[HorseCollisionMod] AUDITION mod not loaded")
	return
end

local target = player.id

if player.this and player.this.id then
	target = player.this.id
end

local first = (BATCH - 1) * PER_BATCH + 1
local last = math.min(first + PER_BATCH - 1, #LINES)

if first > #LINES then
	System.LogAlways("[HorseCollisionMod] AUDITION batch " .. BATCH
			.. " is past the end; there are " .. #LINES .. " lines in "
			.. math.ceil(#LINES / PER_BATCH) .. " batches")
	return
end

System.LogAlways("[HorseCollisionMod] AUDITION batch " .. BATCH
		.. " firing " .. first .. "-" .. last .. " of " .. #LINES)

-- Henry's own gate would suppress most of a batch, since it exists precisely to
-- stop him speaking twice in quick succession. The audition sets the clock back
-- to zero before each send instead of fighting it.
local function speak(index)
	local entry = LINES[index]

	m.RiderVoiceUntil = 0
	m.RiderVoiceRank = 0

	local ok = pcall(function()
		XGenAIModule.SendMessageToEntityData(target, "dialog:monologRequest",
				Utils.makeTable("dialog:monologRequest", {
					alias = entry[1],
					forceOnMuted = true,
					priority = 50,
					canBeDelayed = false,
					overrideContextSuppress = true
				}))
	end)

	System.LogAlways("[HorseCollisionMod] AUDITION " .. index
			.. " alias=" .. entry[1]
			.. " expect=\"" .. entry[2] .. "\""
			.. " sent=" .. tostring(ok))
end

for index = first, last do
	local delay = (index - first) * SPACING_MS

	if delay == 0 then
		speak(index)
	else
		Script.SetTimer(delay, function()
			speak(index)
		end)
	end
end
