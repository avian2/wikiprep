import urllib
import codecs
import re
import sys
import time

# Wikipedia blocks urllib's default UA
class AppURLopener(urllib.FancyURLopener):
	version = "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.1.12) Gecko/20080129 Iceweasel/2.0.0.12 (Debian-2.0.0.12-1)"

urllib._urlopener = AppURLopener()

def getpage(f, title, first):
	print "Downloading", title

	fu = urllib.urlopen("http://en.wikipedia.org/wiki/Special:Export/" + urllib.quote(title))

	dowrite = first

	while True:
		line = fu.readline()

		if not line:
			break

		if not dowrite:
			if re.search(u"<page>", line):
				dowrite = True

		if dowrite:
			f.write(line.decode('utf-8'))
				
			if re.search(u"</page>", line):
				dowrite = False

	fu.close()

def getdepends(title):
	fu = urllib.urlopen("http://en.wikipedia.org/w/index.php?title=" + urllib.quote(title) + "&action=edit")

	text = fu.read()

	fu.close()

	deps = {}

	for a in re.findall(u" title=\"(Template:.*?)\">Template:", text):
		deps[a] = 1

	return deps

try:
	page = sys.argv[1]
except:
	print """Constructs a partial Wikipedia dump containing one page
and all templates it includes

SYNTAX: python getpage.py unique_name

For example "python getpage.py Microsoft" creates a dump in microsoft.xml
that can be used to test if wikiprep.pl properly processes Microsoft's page
"""
	sys.exit(1)

deps = getdepends(page)

f = codecs.open(page.lower() + ".xml", "w", "utf-8")

getpage(f, page, True)

for dep in deps.iterkeys():
	time.sleep(2)	# be nice to wikimedia's servers
	getpage(f, dep, False)

f.write(u"</mediawiki>")

f.close()
