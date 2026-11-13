#!/usr/bin/env python3
"""Quick, network-free Pages build, HTML, links and structured-data gate."""
from collections import Counter
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import unquote, urljoin, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://sanjaygbhat.github.io/wowforever-waypoint-tracker/'
VOID = set('area base br col embed hr img input link meta param source track wbr'.split())


def normalized(text):
    return ' '.join(text.split())


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.ids = set()
        self.links = []
        self.meta = {}
        self.canonical = []
        self.title = ''
        self.faq_questions = []
        self.jsonld = []
        self.question = None
        self.script = None
        self.feed(source)
        self.close()
        assert not self.stack, ('unclosed HTML elements', self.stack)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get('id'):
            assert attrs['id'] not in self.ids, ('duplicate id', attrs['id'])
            self.ids.add(attrs['id'])
        for key in ('href', 'src', 'poster'):
            if attrs.get(key):
                self.links.append(attrs[key])
        if tag == 'meta':
            self.meta[attrs.get('name') or attrs.get('property')] = attrs.get('content', '')
        if tag == 'link' and 'canonical' in attrs.get('rel', '').split():
            self.canonical.append(attrs['href'])
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self.script = ''
        if tag == 'summary' and any(a.get('id') == 'faq' for _, a in self.stack):
            self.question = ''
        if tag not in VOID:
            self.stack.append((tag, attrs))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        assert self.stack and self.stack[-1][0] == tag, ('misnested HTML', tag, self.stack[-3:])
        self.stack.pop()
        if tag == 'script' and self.script is not None:
            self.jsonld.append(json.loads(self.script))
            self.script = None
        if tag == 'summary' and self.question is not None:
            self.faq_questions.append(normalized(self.question))
            self.question = None

    def handle_data(self, text):
        if self.stack and self.stack[-1][0] == 'title':
            self.title += text
        if self.script is not None:
            self.script += text
        elif self.question is not None:
            self.question += text


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def check():
    with tempfile.TemporaryDirectory(prefix='waypoint-site-') as tmp:
        out = Path(tmp) / 'built'
        subprocess.run(['sh', 'tools/build_site.sh', str(out)], cwd=ROOT, check=True,
                       stdout=subprocess.PIPE, text=True)
        pages = {}
        for path in sorted(out.glob('*.html')):
            try:
                page = Page(path.read_text())
                assert normalized(page.title), 'missing title'
                assert page.meta.get('description'), 'missing meta description'
                expected = BASE + ('' if path.name == 'index.html' else path.name)
                assert page.canonical == [expected], ('canonical mismatch', page.canonical, expected)
                assert page.meta.get('og:url') == expected, 'Open Graph URL mismatch'
                for key in ('og:title', 'og:description', 'og:type', 'og:image'):
                    assert page.meta.get(key), ('missing Open Graph tag', key)
                assert page.jsonld, 'missing JSON-LD'
                all_nodes = [n for document in page.jsonld for n in nodes(document)]
                faqs = [n for n in all_nodes if n.get('@type') == 'FAQPage']
                assert len(faqs) == 1, 'expected one FAQPage'
                questions = [normalized(q['name']) for q in faqs[0]['mainEntity']]
                assert len(set(questions)) == len(questions), 'duplicate FAQ schema question'
                assert Counter(questions) == Counter(page.faq_questions), (
                    'FAQ JSON-LD differs from visible questions', set(questions) ^ set(page.faq_questions))
                for q in faqs[0]['mainEntity']:
                    assert q['acceptedAnswer']['text'].strip(), 'empty FAQ answer'
                app = [n for n in all_nodes if n.get('@type') == 'SoftwareApplication']
                assert len(app) == 1 and app[0]['@id'] == BASE + '#app', 'app identity mismatch'
                assert app[0]['offers']['price'] == '0', 'app price mismatch'
                if path.name != 'index.html':
                    article = next(n for n in all_nodes if n.get('@type') == 'Article')
                    assert re.fullmatch(r'\d{4}-\d{2}-\d{2}', article['dateModified'])
                    assert 'Last checked:' in path.read_text() and article['dateModified'] in path.read_text()
                pages[path.name] = page
            except (AssertionError, ValueError, KeyError, StopIteration) as error:
                raise AssertionError(str(path.name) + ': ' + str(error)) from error
        assert pages, 'site has no HTML pages'
        for filename, page in pages.items():
            for link in page.links:
                url = urlsplit(urljoin(BASE + filename, link))
                if (url.scheme, url.netloc) != (urlsplit(BASE).scheme, urlsplit(BASE).netloc):
                    continue
                assert url.path.startswith(urlsplit(BASE).path), (filename, 'link leaves project root', link)
                relative = unquote(url.path[len(urlsplit(BASE).path):]) or 'index.html'
                if relative.endswith('/'):
                    relative += 'index.html'
                target = (out / relative).resolve()
                assert target.is_relative_to(out.resolve()), (filename, 'path escapes site', link)
                assert target.is_file(), (filename, 'broken internal link', link)
                if url.fragment and relative.endswith('.html'):
                    assert unquote(url.fragment) in pages[relative].ids, (filename, 'missing anchor', link)
        sitemap = ET.parse(out / 'sitemap.xml').getroot()
        namespace = {'s': 'http://www.sitemaps.org/schemas/sitemap/0.9'}
        listed = [n.text for n in sitemap.findall('s:url/s:loc', namespace)]
        assert len(set(listed)) == len(listed), 'duplicate sitemap URL'
        assert set(listed) == {p.canonical[0] for p in pages.values()}, 'sitemap must list every HTML page'
        assert len(sitemap.findall('s:url/s:lastmod', namespace)) == len(pages), 'missing sitemap lastmod'
        for lastmod in sitemap.findall('s:url/s:lastmod', namespace):
            assert re.fullmatch(r'\d{4}-\d{2}-\d{2}', lastmod.text or ''), 'bad sitemap date'
        # Do not repeat restricted branding in a checker that guards public copy.
        forbidden = ('map' + 'zeroth', 'eg link', 'efficient games')
        targets = list(out.rglob('*')) + list((ROOT / 'docs/wiki').glob('*.md'))
        targets += [ROOT / 'README.md', ROOT / 'docs/comparison-data.json']
        for path in targets:
            if not path.is_file():
                continue
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            assert '@VERSION@' not in text and '@DATE@' not in text, ('unexpanded placeholder', path)
            assert not any(name in text.lower() for name in forbidden), ('restricted branding', path)
        print('Site checks passed:', len(pages), 'HTML pages; JSON-LD, FAQs, links, sitemap, branding and HTML structure.')


if __name__ == '__main__':
    check()
