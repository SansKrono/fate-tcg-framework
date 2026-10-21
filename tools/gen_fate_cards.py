#!/usr/bin/env python3
"""Generates src/custom/fate/FateData.gd from the card catalog in docs/FATE_TCG_DESIGN.md.

Run from the repository root:  python3 tools/gen_fate_cards.py
"""
import json
import re

DOC = "docs/FATE_TCG_DESIGN.md"
OUT = "src/custom/fate/FateData.gd"

# The most copies of a card in a deck (Section 11.2); unique cards are limited to one
MAX_COPIES = 3

INITIAL = {"Innovation": "I", "Chaos": "C", "Order": "O", "Primal": "P"}
SECTION_DOMAIN = {"14.1": "Innovation", "14.2": "Chaos", "14.3": "Order", "14.4": "Primal"}
# Section 14.5 cards have no domain in the draft; these are assumptions (see design doc, Section 12 item 21).
ADDITIONAL_DOMAIN = {
    "Brogir, Master Artificer": "Innovation",
    "Rarink, Crafty Opportunist": "Innovation",
    "Self-destruction": "Chaos",
    "Sigil Mage": "Order",
    "Holy Healer": "Order",
    "Insightful Investigator": "Order",
    "Toll of War": "Primal",
    "Broadening Influence": "Chaos",
    "No Where to Hide": "Primal",
    "Wave of Fear": "Order",
    "Specter of Hate": "Chaos",
    "Unseen Reach": "Chaos",
    "Battering Ram": "Primal",
    "Goblin Scout Leader": "Primal",
}
KEYWORDS = ["Charge", "Consume", "Embody", "Evolve", "Evolution", "Flip cast", "Indomitable",
            "Limiter", "Savage", "Occupy", "Productive", "Reaction", "Untethered"]



def innate_keywords(effect, card_type):
    """Keywords a creature has by itself (a clause that starts with the keyword), as name -> value.

    Mentions inside other abilities ("gains Savage 1 until end of turn") are not innate. These are
    what the combat rules read at runtime; `_keywords` is only the list of words shown on the card.
    """
    found = {}
    if card_type != "Creature":
        return found
    for clause in re.split(r"[.;]", effect):
        c = clause.strip()
        m = re.match(r"(Charge|Indomitable|Productive|Untethered)\b", c, re.I)
        if m:
            found[m.group(1).capitalize()] = 1
        m = re.match(r"Savage\s*\(?(\d+)\)?", c, re.I)
        if m:
            found["Savage"] = int(m.group(1))
        if re.match(r"Cannot be blocked", c, re.I):
            found["Unblockable"] = 1
        if re.search(r"\bcannot block\b", c, re.I):
            found["Cannot block"] = 1
    return found


text = open(DOC, encoding="utf-8").read()
catalog = text.split("## 14. Card-by-card implementation catalog")[1].split("### 14.6")[0]

cards = {}
order = []
section = None
for line in catalog.splitlines():
    m = re.match(r"### (14\.\d)", line)
    if m:
        section = m.group(1)
        continue
    if not line.startswith("| ") or line.startswith("| Card") or line.startswith("|---"):
        continue
    cols = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cols) < 7:
        continue
    name, cost, typ, sg, effect, mapping, klass = cols[:7]
    name = name.strip()
    cost = cost.replace("(assumed)", "").strip()
    unique = typ.startswith("Unique")
    typ = typ.replace("Unique ", "")
    spell_kind = ""
    if typ.startswith("Spell"):
        card_type = "Spell"
        m2 = re.search(r"\((\w+)\)", typ)
        spell_kind = m2.group(1).capitalize() if m2 else "Regular"
        subtypes = []
    else:
        card_type, _, rest = typ.partition(",")
        subtypes = rest.split() if rest.strip() else []
        card_type = card_type.strip()
    generic = "".join(ch for ch in cost if ch.isdigit())
    pips_count = cost.count("#")
    domain = SECTION_DOMAIN.get(section) or ADDITIONAL_DOMAIN[name]
    pips = INITIAL[domain] * pips_count
    strike = guard = None
    if card_type == "Creature":
        sg = sg.strip()
        if "/" in sg:
            strike, guard = [int(x) for x in sg.split("/")]
        else:
            strike, guard = 0, 1  # stats missing in the draft (placeholder)
    effect = effect.replace("`", "")
    kws = [k for k in KEYWORDS if re.search(r"\b" + re.escape(k) + r"\b", effect, re.I)]
    props = {
        "Type": card_type,
        "Domain": domain,
        "Tags": subtypes + ([spell_kind] if spell_kind else []),
        "Cost": int(generic) if generic else 0,
        "Pips": pips,
    }
    if card_type == "Creature":
        props["Strike"] = strike
        props["Guard"] = guard
    props["Abilities"] = effect
    props["_domains"] = [domain]
    props["_unique"] = unique
    props["_max_allowed"] = 1 if unique else MAX_COPIES
    if spell_kind:
        props["_spell_kind"] = spell_kind
    if kws:
        props["_keywords"] = kws
    inn = innate_keywords(effect, card_type)
    if inn:
        props["_innate_keywords"] = inn
    if section == "14.5":
        props["_domain_assumed"] = True
    if card_type == "Creature" and "/" not in sg:
        props["_stats_placeholder"] = True
    cards[name] = props
    order.append(name)

# Debug card (not in the design doc): its Occupy ability creates a Debug Token (FxDebugCard.gd)
cards["Debug Card"] = {"Type": "Creature", "Domain": "Debug", "Tags": ["Debug"], "Cost": 0, "Pips": "I",
                       "Strike": 1, "Guard": 1, "Abilities": "Occupy: create a Debug Token",
                       "_domains": ["Debug"], "_unique": False, "_max_allowed": 3, "_keywords": ["Occupy"]}
order.insert(0, "Debug Card")

tokens = {
    "Soldier Token": ("Creature", "Order", ["Human", "Soldier", "Token"], 1, 1, "A 1/1 soldier."),
    "Goblin Token": ("Creature", "Primal", ["Goblin", "Token"], 1, 1, "A 1/1 goblin."),
    "Iron Automaton Token": ("Creature", "Innovation", ["Construct", "Token"], 3, 3, "A 3/3 iron automaton."),
    "Automaton Token": ("Creature", "Innovation", ["Construct", "Token"], 1, 1, "A 1/1 automaton."),
    "Debug Token": ("Creature", "Debug", ["Debug", "Token"], 1, 1, "A 1/1 debug token."),
}
relic_tokens = {
    "Battle Hammer Token": ("Innovation", "Attached creature gains +2 Strike."),
    "Soul Spear Token": ("Order", "Consume: deal 2 damage to any target."),
}
for n, (t, d, tags, s, g, a) in tokens.items():
    cards[n] = {"Type": t, "Domain": d, "Tags": tags, "Cost": 0, "Pips": "", "Strike": s, "Guard": g,
                "Abilities": a, "_domains": [d], "_unique": False, "_max_allowed": 0,
                "_token": True, "_hide_in_deckbuilder": True}
for n, (d, a) in relic_tokens.items():
    cards[n] = {"Type": "Relic", "Domain": d, "Tags": ["Token"], "Cost": 0, "Pips": "", "Abilities": a,
                "_domains": [d], "_unique": False, "_max_allowed": 0, "_token": True,
                "_hide_in_deckbuilder": True}

# Doctrines (Section 10.2 of the design doc). Tier 1 to 3 per branch; faith cost equals the tier.
doctrine_rows = re.findall(r"^\| ([COPI]\d) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|", text, re.M)
branch = {"C": "Chaos", "O": "Order", "P": "Primal", "I": "Innovation"}
doctrines = {}
for did, dname, goal, reward in doctrine_rows:
    dname = dname.strip()
    tier = int(did[1])
    d = branch[did[0]]
    doctrines[dname] = {
        "Type": "Doctrine", "Domain": d, "Tags": ["Tier " + str(tier)], "Cost": tier, "Pips": "",
        "Abilities": "Goal: " + goal.strip() + "\nReward: " + reward.strip(),
        "_domains": [d], "_unique": True, "_max_allowed": 1, "_hide_in_deckbuilder": True,
        "_doctrine_id": did,
    }


def gd(v, indent=2):
    pad = "\t" * indent
    if isinstance(v, dict):
        inner = "".join(f"{pad}\t{json.dumps(k)}: {gd(x, indent + 1)},\n" for k, x in v.items())
        return "{\n" + inner + pad + "}"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return "[" + ", ".join(gd(x, indent) for x in v) + "]"
    return json.dumps(v, ensure_ascii=False)


out = ["# GENERATED by tools/gen_fate_cards.py from docs/FATE_TCG_DESIGN.md. Do not edit by hand;",
       "# change the design document catalog (or the generator) and regenerate.",
       "#",
       "# Card definitions for the Fate TCG proof of concept. These are deliberately NOT placed in",
       "# PATH_SETS: FateGame.register_cards() merges them into cfc.card_definitions at runtime, so",
       "# the framework demo sets and their unit tests are unaffected.",
       "class_name FateData",
       "extends RefCounted",
       "",
       "const SET := \"Dominarus\"",
       "",
       "const CARDS := " + gd({n: cards[n] for n in order}, 0),
       "",
       "const TOKENS := " + gd({n: cards[n] for n in list(tokens) + list(relic_tokens)}, 0),
       "",
       "const DOCTRINES := " + gd(doctrines, 0),
       ""]
open(OUT, "w", encoding="utf-8").write("\n".join(out))
print(len(order), "cards,", len(tokens) + len(relic_tokens), "tokens,", len(doctrines), "doctrines")
