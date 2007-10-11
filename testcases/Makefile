LOGS =	images.log \
	urlencode.log \
	parserfunctions.log \
	anchors.log \
	redir.log

all: $(LOGS)

%.log: %.xml
	perl ../wikiprep.pl -f $<
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

.PHONY: clean
