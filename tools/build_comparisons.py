#!/usr/bin/env python3
"""Render reviewed comparison data to flat Pages files and the wiki (offline).

Edit docs/comparison-data.json, then run python3 -B tools/build_comparisons.py.
Research dates are explicit: rebuilding must not imply that sources were rechecked.
The ordinary site build only substitutes version/date placeholders in flat files.
"""
import copy
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://sanjaygbhat.github.io/wowforever-waypoint-tracker/'
REPO = 'https://github.com/sanjaygbhat/wowforever-waypoint-tracker/'
DATA = json.loads((ROOT / 'docs/comparison-data.json').read_text())
DATE = DATA['checked']
ROWS = DATA['addons']
SOURCES = {s['url']: s for s in DATA['sources']}
OWN_SOURCES = [REPO + 'blob/main/' + p for p in
               ('README.md', 'docs/CURSEFORGE.md', 'CHANGELOG.md')]
FIELDS = [('support', 'Official client support'), ('price', 'Price'),
          ('licence', 'Licence'), ('arrow', 'Arrow'), ('waypoints', 'Waypoints'),
          ('quest_map', 'Quest objectives on map'), ('search', 'NPC / item search'),
          ('nearest', 'Nearest services / trainers'), ('routing', 'Routing'),
          ('alerts', 'Rare / treasure alerts'), ('tomtom', 'TomTom API'),
          ('languages', 'Languages')]
OWN = dict(slug='waypoint-tracker', name=DATA['baseline'],
           support='Forever 1.60.1 / interface 16001', price='Free', licence='MIT',
           arrow='3D arrow', waypoints='/way, map clicks, Find',
           quest_map='Follows native quest POIs; quest Find',
           search='Quests, NPCs, enemies, objects, items',
           nearest='Shipped services; complete trainer database, all 9 classes and 12 professions; weapon and riding trainers',
           routing='Real routes: flights, boats, zeppelins, tram, hearthstone, teleports',
           alerts='Treasure hunt (beta), opt-in',
           tomtom='Compatible waypoint API; yields to TomTom',
           languages='English, German, French, Spanish, Portuguese, Russian, Korean, Simplified/Traditional Chinese')
INTRO = ('Waypoint Tracker combines a 3D waypoint arrow with Find for quests, NPCs, '
         'enemies, objects and items on WoW Forever. Real routes is a standard feature, '
         'on by default: it plans the fastest known usable journey, including flight paths, '
         'boats, zeppelins, the tram, hearthstone and usable teleports. The default Safe route '
         'preference asks before a quicker route crosses dangerous ground; Always fastest is optional.')
NEAREST = DATA['nearest']
BRIDGE = ('Waypoint Tracker accepts supported TomTom waypoint calls when TomTom is absent. '
          'When TomTom is installed, Waypoint Tracker leaves /way and the waypoint API to it; '
          '/wp remains available.')
METHOD = DATA['method']
LEGEND = DATA['matrix_legend']
DECISIONS = [
    ('A 3D arrow, NPC/item/quest lookup and nearest trainers',
     'Use Waypoint Tracker for Find, Nearest and Real routes to a destination you choose.'),
    ('Coordinate waypoints and arrow themes',
     'TomTom provides that workflow and lists Forever support; compare its arrow controls with Waypoint Tracker’s Find and travel tools.'),
    ('A map overview of quests',
     'Questie documents quest starts, objectives, turn-ins and journey history. Waypoint Tracker adds selected-destination navigation.'),
    ('A suggested leveling sequence',
     'Use a guide such as Zygor, RestedXP, Guidelime, WoW-Pro, Polestar or Wayfinder Forever. Check Forever coverage and guide maturity; a travel planner is a different task from choosing quests.'),
    ('Browsable location pins',
     'Use HandyNotes with the relevant Forever plugin. Rare, treasure, service, transport and book plugins have different datasets.'),
    ('A replacement map workspace',
     'Consider Carbonite All in One, OpenMap or Endless Map; Mapster and Leatrix Maps offer map adjustments.'),
    ('Gathering, collections or dedicated alerts',
     'Choose the specialist workflow: GatherMate2 or a Forever gathering tool, or RareScanner/SilverDragon for rare detection. These roles can complement destination navigation.'),
]
HUB_FAQ = [
    ('Which WoW Forever addon combines a waypoint arrow with NPC and item search?',
     'Waypoint Tracker combines a 3D arrow with Find for quests, NPCs, enemies, objects and items. It is free under the MIT licence and targets Forever 1.60.1, interface 16001.'),
    ('Does Classic Era support establish WoW Forever compatibility?',
     'No. Check for an explicit Forever release or official Forever documentation. Upstream pfQuest documents Vanilla/TBC clients; a Forever build was not verified in the checked sources.'),
    ('Can TomTom-compatible addons send waypoints to Waypoint Tracker?', BRIDGE),
    ('How do I find the nearest class or profession trainer in WoW Forever?', NEAREST),
    ('Should I use a leveling guide or Waypoint Tracker?',
     'Use a leveling guide when you want instructions about which quests to accept, complete and turn in. Use Waypoint Tracker for Find, the shipped Nearest database and travel to your chosen destination.'),
]


def esc(value):
    return html.escape(str(value), quote=True)


def para(text):
    return '<p>' + esc(text) + '</p>\n'


def source_links(urls):
    return '<ul class="sources">' + ''.join(
        '<li><a href="' + esc(u) + '">' + esc(u) + '</a> — checked ' + DATE + '</li>'
        for u in urls) + '</ul>'


def markdown_sources(urls):
    return '\n'.join('- [Official source](' + u + ') — checked ' + DATE for u in urls)


def both(row):
    return row.get('both', 'Use ' + row['name'] + ' for its specialist workflow and '
                   'Waypoint Tracker for Find and travel to your chosen destination. '
                   'Use /wp when another addon owns /way.')


def cell(value):
    return '—' if value == 'Not stated' else value


def matrix(rows):
    content = '<div class="table-scroll" role="region" aria-label="Addon feature matrix" tabindex="0">'
    content += '<table><caption>Documented features — last checked ' + DATE + '</caption><thead><tr><th scope="col">Addon</th>'
    content += ''.join('<th scope="col">' + esc(label) + '</th>' for _, label in FIELDS)
    content += '</tr></thead><tbody>'
    for row in rows:
        target = '#waypoint-tracker' if row is OWN else '#' + row['slug']
        content += '<tr><th scope="row"><a href="' + target + '">' + esc(row['name']) + '</a></th>'
        content += ''.join('<td>' + esc(cell(row[key])) + '</td>' for key, _ in FIELDS) + '</tr>'
    return content + '</tbody></table></div>\n' + para(LEGEND)


def markdown_matrix(rows):
    def clean(s):
        return str(cell(s)).replace('|', '\\|').replace('\n', ' ')
    lines = ['| Addon | ' + ' | '.join(label for _, label in FIELDS) + ' |',
             '|' + '---|' * (len(FIELDS) + 1)]
    for row in rows:
        lines.append('| ' + ' | '.join(clean(row[k]) for k in ['name'] + [k for k, _ in FIELDS]) + ' |')
    return '\n'.join(lines)


def faq_html(faq):
    return '<section id="faq"><h2>Questions and answers</h2>\n' + ''.join(
        '<details><summary>' + esc(q) + '</summary>' + para(a) + '</details>\n'
        for q, a in faq) + '</section>\n'


def shell(filename, title, description, body, faq, items):
    url = BASE + filename
    index = (ROOT / 'site/index.html').read_text()
    graph = json.loads(index.split('<script type="application/ld+json">', 1)[1].split('</script>', 1)[0])
    app = copy.deepcopy(next(n for n in graph['@graph'] if n['@type'] == 'SoftwareApplication'))
    structured = {'@context': 'https://schema.org', '@graph': [
        {'@type': 'Article', '@id': url + '#article', 'url': url, 'headline': title,
         'description': description, 'dateModified': DATE, 'inLanguage': 'en',
         'author': {'@type': 'Person', 'name': 'sanjaygbhat', 'url': 'https://github.com/sanjaygbhat'},
         'about': {'@id': BASE + '#app'}, 'citation': list(dict.fromkeys(
             OWN_SOURCES + [s for row in items for s in row['sources']]))},
        app,
        {'@type': 'FAQPage', '@id': url + '#faq', 'mainEntity': [
            {'@type': 'Question', 'name': q, 'acceptedAnswer': {'@type': 'Answer', 'text': a}}
            for q, a in faq]},
        {'@type': 'ItemList', 'name': 'Addons compared', 'itemListElement': [
            {'@type': 'ListItem', 'position': i, 'name': row['name'], 'url': url + '#' + row['slug']}
            for i, row in enumerate(items, 1)]}
    ]}
    jsonld = json.dumps(structured, ensure_ascii=False, indent=2).replace('<', '\\u003c')
    return f'''<!doctype html>
<!-- Generated by tools/build_comparisons.py from docs/comparison-data.json. -->
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="{url}">
<meta name="robots" content="index, follow, max-image-preview:large">
<meta name="color-scheme" content="dark light">
<link rel="icon" type="image/png" href="img/logo-400.png">
<link rel="stylesheet" href="comparison.css">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Waypoint Tracker">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(description)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{BASE}img/social-preview.png">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">
{jsonld}
</script>
</head>
<body>
<a class="skip" href="#content">Skip to comparison</a>
<header class="bar"><div class="wrap">
<a class="brand" href="./"><img src="img/logo-400.png" width="34" height="34" alt="">Waypoint Tracker</a>
<nav aria-label="Main"><a href="./">Addon home</a><a href="compare.html">Compare addons</a><a href="./#install">Install</a></nav>
</div></header>
<main class="wrap" id="content">
<p class="kicker">WoW Forever · addon comparison</p>
<h1>{esc(title)}</h1>
{body}
{faq_html(faq)}
<section id="method"><h2>How we compared</h2>
<p class="checked">Last checked: <time datetime="{DATE}">{DATE}</time> · {esc(DATA['baseline'])}</p>
{para(METHOD)}
<h3>Waypoint Tracker 1.4.1 sources</h3>{source_links(OWN_SOURCES)}
<h3>Competitor sources</h3>{source_links(list(dict.fromkeys(s for row in items for s in row['sources'])))}
</section>
</main>
<footer class="wrap"><p><a href="compare.html">All addon comparisons</a> · <a href="./">Waypoint Tracker home</a> · <a href="{REPO}wiki/Comparison-with-Other-Addons">Wiki comparison</a></p>
<p>Waypoint Tracker @VERSION@ · <a href="{REPO}">Source</a> · MIT licence. World of Warcraft is a trademark of Blizzard Entertainment. Independent addon project.</p></footer>
</body>
</html>
'''


def own_html():
    return ('<section id="waypoint-tracker"><h2>Waypoint Tracker: 3D arrow + Find</h2>'
            + para(INTRO) + para(NEAREST) + para(BRIDGE)
            + para('Treasure hunt (beta) and Route sharing & votes (beta) are opt-in and off by default. '
                   'Known spots are places to check for rares and chests.')
            + '</section>')


def section(row, pair=False):
    result = '<section id="' + row['slug'] + '"><h2>' + esc(row['name']) + ' vs Waypoint Tracker</h2>'
    result += para(row['summary'] + ' ' + row['choice'])
    result += '<h3>Can I use both?</h3>' + para(both(row))
    if row.get('pair') and not pair:
        result += para_link('Full ' + row['name'] + ' comparison', pair_filename(row))
    return result + '</section>\n'


def para_link(text, href):
    return '<p><a href="' + esc(href) + '">' + esc(text) + '</a></p>'


def pair_filename(row):
    return 'waypoint-tracker-vs-' + {'restedxp-guide': 'restedxp'}.get(row['slug'], row['slug']) + '.html'


def main():
    site = ROOT / 'site'
    hub_title = 'WoW Forever addon comparison: Waypoint Tracker vs TomTom, Questie, pfQuest and more'
    description = 'Compare WoW Forever arrows, quest helpers, leveling guides, NPC finders and map addons. Official sources, client support, features and when to use both.'
    body = para(DATA['hub_answer']) + para_link('Install Waypoint Tracker', './#install')
    body += '<section id="choose"><h2>Which should I use?</h2><dl>'
    body += ''.join('<dt>' + esc(q) + '</dt><dd>' + esc(a) + '</dd>' for q, a in DECISIONS) + '</dl></section>'
    body += '<nav class="contents" aria-label="Addons compared"><h2>Jump to an addon</h2><ul>'
    body += ''.join('<li><a href="#' + r['slug'] + '">' + esc(r['name']) + '</a></li>' for r in ROWS) + '</ul></nav>'
    body += '<section id="matrix"><h2>Feature matrix</h2>'
    body += para('Scroll horizontally for all features. Each addon name leads to its comparison; dated official sources are at the bottom.')
    body += matrix([OWN] + ROWS) + '</section>' + own_html()
    body += ''.join(section(row) for row in ROWS)
    body += '<section><h2>Corrections and updates</h2>' + para_link(
        'Report a changed feature or Forever release with its official URL', REPO + 'issues') + '</section>'
    (site / 'compare.html').write_text(shell('compare.html', hub_title, description, body, HUB_FAQ, ROWS))
    pairs = []
    for row in ROWS:
        if not row.get('pair'):
            continue
        filename = pair_filename(row)
        pairs.append((row, filename))
        title = 'Waypoint Tracker vs ' + row['name'] + ' for WoW Forever'
        description = row['choice']
        faq = [
            ('Should I choose ' + row['name'] + ' or Waypoint Tracker?', row['summary'] + ' ' + row['choice']),
            ('Can I use ' + row['name'] + ' with Waypoint Tracker?', both(row)),
            ('Does ' + row['name'] + ' officially support WoW Forever?', row['support'] + '. Check the linked official release and its content coverage before installing.'),
            ('How do I find the nearest trainer with Waypoint Tracker?', NEAREST),
        ]
        content = para(row['summary'] + ' ' + row['choice']) + para_link('Compare all navigation and quest addons', 'compare.html')
        content += '<section><h2>Features and client support</h2>' + matrix([OWN, row]) + '</section>'
        content += section(row, pair=True) + own_html()
        if row['slug'] == 'handynotes':
            content += '<section><h2>Choose a Forever plugin</h2>'
            content += para('The framework and each plugin have separate support requirements. '
                            'For rares and treasures compare HandyNotes: WoW Forever and '
                            'HandyNotes: Rares and Treasures Forever; for services consider '
                            'HandyNotes_NPCs-forever; for travel points consider HandyNotes_Traveler.')
            content += '<ul>' + ''.join('<li><a href="compare.html#' + r['slug'] + '">' + esc(r['name']) + '</a></li>'
                                       for r in ROWS if r['slug'].startswith('handynotes-')) + '</ul></section>'
        if row['slug'] in ('zygor', 'restedxp-guide'):
            content += '<section><h2>Guide steps and travel solve different questions</h2>'
            content += para('A leveling guide chooses a sequence of quests and explains what to do next. '
                            'Real routes plans travel to the destination you selected.')
            content += para_link('Compare free guide alternatives and guide maturity', 'compare.html#guidelime') + '</section>'
        content += '<section><h2>More comparisons</h2><ul>' + ''.join(
            '<li><a href="' + pair_filename(r) + '">' + esc(r['name']) + ' vs Waypoint Tracker</a></li>'
            for r in ROWS if r.get('pair') and r is not row) + '</ul></section>'
        (site / filename).write_text(shell(filename, title, description, content, faq, [row]))
    wiki = '# Comparison with Other Addons\n\n' + DATA['hub_answer'] + '\n\n'
    wiki += '[Comparison hub](' + BASE + 'compare.html) · [Waypoint Tracker home](' + BASE + ')\n\n'
    wiki += INTRO + '\n\n' + NEAREST + '\n\n' + BRIDGE + '\n\n'
    wiki += 'Treasure hunt (beta) and Route sharing & votes (beta) are off by default.\n\n'
    wiki += '## Which should I use?\n\n' + '\n'.join('- **' + q + ':** ' + a for q, a in DECISIONS) + '\n\n'
    wiki += '## Feature matrix\n\n' + LEGEND + '\n\n'
    wiki += markdown_matrix([OWN] + ROWS) + '\n\n'
    for row in ROWS:
        wiki += '## ' + row['name'] + ' vs Waypoint Tracker\n\n' + row['summary'] + ' ' + row['choice'] + '\n\n'
        wiki += '**Can I use both?** ' + both(row) + '\n\n'
        if row.get('pair'):
            wiki += '[Full pair comparison](' + BASE + pair_filename(row) + ')\n\n'
    wiki += '## Questions and answers\n\n' + '\n\n'.join('**' + q + '**\n\n' + a for q, a in HUB_FAQ) + '\n'
    wiki += '\n## How we compared\n\nLast checked: **' + DATE + '**. Baseline: **' + DATA['baseline'] + '**.\n\n' + METHOD
    wiki += '\n\n### Waypoint Tracker sources\n\n' + markdown_sources(OWN_SOURCES)
    wiki += '\n\n### Competitor sources\n\n' + markdown_sources(list(dict.fromkeys(s for row in ROWS for s in row['sources']))) + '\n'
    (ROOT / 'docs/wiki/Comparison-with-Other-Addons.md').write_text(wiki)
    pages = [''] + ['compare.html'] + [filename for _, filename in pairs]
    (site / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(
            '  <url><loc>' + BASE + p + '</loc><lastmod>@DATE@</lastmod></url>\n' for p in pages) + '</urlset>\n')
    llms = (site / 'llms.txt').read_text().split('\n## Comparisons\n')[0].rstrip() + '\n\n## Comparisons\n\n'
    llms += 'Official sources last checked ' + DATE + '; publisher feature claims, not live-client tests. '
    llms += 'Classic Era support alone does not establish Forever compatibility.\n\n'
    llms += '- [Addon comparison hub](' + BASE + 'compare.html): features, client support and which role each addon serves.\n'
    llms += ''.join('- [Waypoint Tracker vs ' + r['name'] + '](' + BASE + f + '): ' + r['choice'] + '\n' for r, f in pairs)
    (site / 'llms.txt').write_text(llms)
    print('Rendered comparison hub,', len(pairs), 'pair pages, wiki, sitemap and llms comparisons.')


if __name__ == '__main__':
    main()
