"""CHANGELOG.md -> the post that goes in a Discord channel.

Run by .github/workflows/release.yml the moment a tag is packaged, so a
release announces itself. It is also the ONE implementation of this format:
ZwoelfStuff-internal/changelog.py imports it rather than keeping a second
copy, because two copies of a formatter drift the first time one of them
learns something the other does not.

WHAT DISCORD ACTUALLY TAKES, checked against its own formatting docs:

  * `#`, `##`, `###` are headings and `-# text` is SUBTEXT - small and grey,
    which is exactly what a sentence of explanation under a headline wants to
    be. Both must start the line, and NEITHER works inside a list item. That
    is why the main entries are not bullets: a bullet cannot carry subtext,
    so a list comes out as a wall of one size however it is worded.
  * `**bold**`, `*italic*`, `` `code` ``, `> quote` and `||spoiler||` render.
  * MASKED LINKS - `[text](url)` - render in WEBHOOK content, which is what
    this posts through, but NOT in a message a person types. So the link at
    the bottom is safe here and is written out in the copy-and-paste version.
  * 2000 characters a message. Split between BLOCKS, so a headline never
    lands in one message with its explanation in the next.

THE SHAPE, which CHANGELOG.md already writes without meaning to: every entry
opens with a bolded sentence and then explains itself. That is a headline and
a caption. So the bold lead is the line you read, the rest is subtext under
it, trimmed to two sentences - the full reasoning is worth having and is not
worth a Discord post, and it is one click away in the addon.

Nothing is posted unless DISCORD_WEBHOOK is set in the repository's secrets.
Absent, this exits quietly: an addon that starts announcing itself to a
channel nobody set up is worse than one that says nothing.
"""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

DISCORD_LIMIT = 2000
CAPTION = 240

BADGES = {
    "Added": "✨",
    "Fixed": "\U0001f527",
    "Changed": "\U0001f501",
    "Removed": "\U0001f5d1️",
    "Deprecated": "⚠️",
    "Security": "\U0001f512",
}

MONTHS = ("January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December")


###########################################################################
# Reading
###########################################################################
def read(path):
    with io.open(path, encoding="utf-8-sig") as handle:
        return handle.read()


def parse(text):
    """CHANGELOG.md -> [{version, date, sections: [(name, [bullet, ...])]}].

    Continuation lines are joined back into their bullet: the file is hard
    wrapped for reading in an editor, and every consumer wants the sentence
    back in one piece.
    """
    versions, version, section = [], None, None

    for line in text.splitlines():
        head = re.match(r"^##\s+\[([^\]]+)\]\s*-\s*(.+?)\s*$", line)
        if head:
            version = {"version": head.group(1), "date": head.group(2),
                       "sections": []}
            versions.append(version)
            section = None
            continue

        if version is None:
            continue

        sub = re.match(r"^###\s+(.+?)\s*$", line)
        if sub:
            section = (sub.group(1), [])
            version["sections"].append(section)
            continue

        if section is None:
            continue

        bullet = re.match(r"^-\s+(.*)$", line)
        if bullet:
            section[1].append(bullet.group(1).strip())
        elif line.strip() and section[1]:
            section[1][-1] += " " + line.strip()

    return versions


def find(versions, wanted):
    for version in versions:
        if version["version"] == wanted:
            return version
    return None


###########################################################################
# Shaping
###########################################################################
def spoken_date(iso):
    """2026-08-10 -> 10 August 2026. A post is read, not sorted."""
    match = re.match(r"^(\d{4})-(\d{2})-(\d{2})$", iso.strip())
    if not match:
        return iso
    year, month, day = (int(part) for part in match.groups())
    if not 1 <= month <= 12:
        return iso
    return "%d %s %d" % (day, MONTHS[month - 1], year)


def unmask(text):
    """[text](url) -> text (url), for the version a person pastes."""
    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r"\1 (\2)", text)


def bite(text, clauses=False):
    """The first sentence, and what is left. Neither one padded.

    With `clauses`, a colon or a semicolon ends it too. That is for pulling a
    trailing half-sentence back INTO a headline: a full stop can be three
    clauses away, and a headline that runs to two lines is not one.
    """
    match = re.search(r"[.!?:;](\s|$)" if clauses else r"[.!?](\s|$)", text)
    if not match:
        return text.strip(), ""
    return text[:match.end()].strip().rstrip(":;"), text[match.end():].strip()


def headline(bullet):
    """An entry into the line you read and the line under it.

    EXCEPT WHEN THE SENTENCE CARRIES ON PAST THE BOLD - `**"Tank stuff" is
    now "M+ and raid stuff"** in the settings rail`. Cut there, the caption
    opens in lower case halfway through a thought. A remainder that starts
    small, or on a bracket, is not a caption; it is the rest of the headline.
    """
    match = re.match(r"^\*\*(.+?)\*\*(.*)$", bullet, re.S)
    if not match:
        return None, bullet.strip()

    lead, rest = match.group(1).strip(), match.group(2).strip()

    # The punctuation that JOINED the two halves belongs to neither of them.
    joiner = " - " if rest[:1] in "-–—" else " "
    rest = rest.lstrip("-–—:;, ").strip()

    if rest and (rest[0].islower() or rest[0] == "("):
        tail, rest = bite(rest, clauses=True)
        lead = (lead.rstrip(".") + joiner + tail).strip()

    return lead, rest


def caption(text, limit=CAPTION):
    """The first sentence or two, whole. Never cut mid-word or mid-clause."""
    text = text.strip().lstrip(",;:").strip()

    # It is a LINE now, wherever it was cut from. A line that opens in lower
    # case reads as the second half of something the reader cannot see.
    if text[:1].islower():
        text = text[0].upper() + text[1:]

    if len(text) <= limit:
        return text

    cut = text[:limit]
    for stop in (". ", "! ", "? "):
        at = cut.rfind(stop)
        if at > 60:
            return cut[:at + 1]
    at = cut.rfind(" ")
    return (cut[:at] if at > 60 else cut).rstrip(" ,;:-") + " ..."


def to_discord(version, link=None, masked=False):
    """One version as the message to post, split when it has to be.

    Blocks, not lines: a headline and its subtext are one thing and must not
    end up in two different messages. `masked` says whether a link may be
    written as [text](url) - true through a webhook, false for a paste.
    """
    blocks = [["## \U0001f6e1️ ZwoelfStuff " + version["version"],
               "-# " + spoken_date(version["date"])]]

    for name, bullets in version["sections"]:
        # A section the changelog invented gets no badge rather than a
        # stand-in one: a bullet character in front of a heading reads as a
        # list item that lost its list.
        badge = BADGES.get(name)
        blocks.append(["", "### " + (badge + " " + name if badge else name)])

        first = True
        for bullet in bullets:
            lead, rest = headline(bullet if masked else unmask(bullet))
            gap = [] if first else [""]
            first = False

            if not lead:
                blocks.append(gap + ["- " + caption(rest)])
                continue

            # The full stop belongs INSIDE the bold, or the line ends on a
            # loose dot hanging off the end of it.
            block = gap + ["**%s.**" % lead.rstrip(".")]
            rest = caption(rest)
            if rest:
                block.append("-# " + rest)
            blocks.append(block)

    if link:
        blocks.append(["", "-# " + ("[Download](%s)" % link if masked
                                    else "Download: " + link)])
    else:
        blocks.append(["", "-# Every word of it in the addon: `/zs` -> Changelog"])

    return split(blocks)


def split(blocks):
    """Blocks into messages of at most DISCORD_LIMIT characters.

    The marker's own length is held back before anything is packed, or a part
    that fits exactly stops fitting once it is stamped.
    """
    room = DISCORD_LIMIT - 16
    parts, current, length = [], [], 0

    for block in blocks:
        cost = sum(len(line) + 1 for line in block)
        if length + cost > room and current:
            parts.append(current)
            current, length = [], 0
            # A block that opens a part must not open it with a blank line.
            block = [line for line in block if line.strip()] or block
            cost = sum(len(line) + 1 for line in block)
        current.extend(block)
        length += cost

    if current:
        parts.append(current)

    if len(parts) == 1:
        return ["\n".join(parts[0]).strip() + "\n"]

    return [("\n".join(part).strip() + "\n-# (%d/%d)\n" % (index, len(parts)))
            for index, part in enumerate(parts, 1)]


###########################################################################
# Posting
###########################################################################
def post(webhook, message):
    payload = json.dumps({
        "username": "ZwoelfStuff",
        "content": message,
        # A release note is not a conversation: nobody wants a ping for it.
        "allowed_mentions": {"parse": []},
    }).encode("utf-8")

    request = urllib.request.Request(
        webhook, data=payload,
        headers={"Content-Type": "application/json",
                 "User-Agent": "ZwoelfStuff-release"})
    with urllib.request.urlopen(request, timeout=20) as answer:
        return answer.status


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    tag = None
    link = None
    source = "CHANGELOG.md"
    for index, arg in enumerate(argv):
        if arg == "--tag" and index + 1 < len(argv):
            tag = argv[index + 1]
        elif arg == "--link" and index + 1 < len(argv):
            link = argv[index + 1]
        elif arg == "--changelog" and index + 1 < len(argv):
            source = argv[index + 1]

    webhook = os.environ.get("DISCORD_WEBHOOK", "").strip()
    if not webhook:
        print("no DISCORD_WEBHOOK set - nothing announced, on purpose.")
        return 0

    versions = parse(read(source))
    version = find(versions, tag) if tag else (versions[0] if versions else None)
    if not version:
        # NOT AN ERROR. A tag with no changelog entry is a thing that
        # happens, and failing the release over an announcement would be the
        # tail wagging the dog - the addon is already on CurseForge by now.
        print("no changelog entry for %s - nothing announced." % tag)
        return 0

    parts = to_discord(version, link=link, masked=True)
    for index, message in enumerate(parts, 1):
        try:
            status = post(webhook, message)
        except (urllib.error.URLError, urllib.error.HTTPError) as problem:
            print("message %d of %d did not go out: %s"
                  % (index, len(parts), problem))
            return 0
        print("message %d of %d posted (%s)" % (index, len(parts), status))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
