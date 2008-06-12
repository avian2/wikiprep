LOGS =	images.log \
	urlencode.log \
	parserfunctions.log \
	anchors.log \
	redir.log \
	categories.log \
	templates.log \
	disambig.log \
	order.log \
	citebook.log \
	gallery.log \
	unicode.log \
	anchorspace.log \
	citeweb.log \
	missinganchors.log \
	infobox.log \
	nowiki.log \
	imagemap.log \
	enwiki-20080103-pages-articles.log \
	xmlcomments.log \
	nestedtables.log \
	div.log \
	languages.log \
	barzilla.log \
	pagename.log \
	ifeq.log \
	asse.log \
	hurt.log \
	microsoft.log \
	microsoft2.log \
	window.log \
	intel.log \
	nonfreegamecover.log \
	olympics.log \
	tibet.log \
	externalurls.log \
	coord.log \
	riemann.log \
	carbon.log \
	dates.log \
	related.log \
	css.log \
	whitespace.log \
	kaon2.log \
	segfault.log

all: test

test: clean $(LOGS) compare

%.log: %.xml
	perl ../wikiprep.pl -log -f $< >/dev/null
clean:
	rm -f *.anchor_text
	rm -f *.anchor_text.sorted
	rm -f *.external_anchors
	rm -f *.cat_hier
	rm -f *.hgw.xml
	rm -f *.local.xml
	rm -f *.log
	rm -f *.prescan
	rm -f *.related_links
	rm -f *.stat.categories
	rm -f *.stat.inlinks
	rm -f *.redir.xml
	rm -f *.disambig
	rm -f *.min_local_id
	rm -f *.version
	rm -rf *.templates

compare:
	./compare

.PHONY: clean compare test all
