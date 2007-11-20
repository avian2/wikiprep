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
	citeweb.log

all: $(LOGS) compare

%.log: %.xml
	perl ../wikiprep.pl -log -f $<
clean:
	rm -f *.anchor_text
	rm -f *.anchor_text.sorted
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

compare:
	./compare

.PHONY: clean compare
