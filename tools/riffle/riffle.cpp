#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>
#include <map>

using namespace std;

#define PATH_LEN		1024

#define LINE_BUFFER_LEN		(10 * 1024 * 1024)
#define TITLE_BUFFER_LEN	(1024 * 1024)

#define FINISH_STRING		"</mediawiki>\n"

#define PAGE_START_STRING	"  <page>\n"
#define PAGE_END_STRING		"  </page>\n"

#define TITLE_PREFIX		"    <title>"
int title_prefix_len;
#define TITLE_POSTFIX		"</title>\n"

char *line_buffer;
char *title_buffer;

struct page_info {
	string path;
	bool replaced;
};

map<string, page_info> page_index;

/* Very fast, very brittle XML parsing */
int copy_preamble(FILE *in, FILE *out)
{
	while(1) {
		char *r=fgets(line_buffer, LINE_BUFFER_LEN, in);

		if(r == NULL) {
			/* End of file */
			return 1;
		}

		if(!strcmp(line_buffer, PAGE_START_STRING)) {
			return 0;
		}

		fputs(line_buffer, out);
	}
}

int finish_page(FILE *in, FILE *out)
{
	while(1) {
		char *r=fgets(line_buffer, LINE_BUFFER_LEN, in);

		if(r == NULL) {
			/* End of file */
			return 1;
		}

		fputs(line_buffer, out);

		if(!strcmp(line_buffer, PAGE_END_STRING)) {
			return 0;
		}
	}
}

int scan_to_title(FILE *in, char *title_buff)
{
	while(1) {
		char *r=fgets(line_buffer, LINE_BUFFER_LEN, in);

		if(r == NULL) {
			/* End of file */
			return 1;
		}

		if(!strncmp(line_buffer, TITLE_PREFIX, title_prefix_len)) {
			char *loc = strstr(line_buffer, TITLE_POSTFIX);

			if(loc == NULL) {
				fprintf(stderr, "ERROR: malformed line: %s\n", line_buffer);
				return 1;
			}

			/* terminate string at the start of postfix */
			loc[0] = 0;

			char *begin = line_buffer + title_prefix_len;

			strcpy(title_buff, begin);

			return 0;
		}
	}
}

/* Scan chunks */
int scan_chunks(char *tracker_path)
{
	char path[PATH_LEN];
	int n;

	for(n = 0; n < 10000; n++) {
		snprintf(path, PATH_LEN, "%s/%04d", tracker_path, n);

		FILE *in = fopen(path, "r");
		if(in == NULL) break;

		int r = scan_to_title(in, title_buffer);
		if(r) {
			fprintf(stderr, "ERROR: unexpected end of file: %s\n", 
									path);
		}

		page_info i;
		i.path = string(path);
		i.replaced = false;

		page_index[ string(title_buffer) ] = i;

		fclose(in);
	}

	fprintf(stderr, "loaded info about %d updated pages\n", n);

	return 0;
}

int riffle_dump(FILE *in, FILE *out)
{
	int r;

	int old_pages = 0, updated_pages = 0, new_pages = 0;

	r = copy_preamble(in, out);
	if(r) {
		fprintf(stderr, "ERROR: unexpected end while copying preample\n");
		return 1;
	}

	while(1) {
		r = scan_to_title(in, title_buffer);
		if(r) break;

		fputs(PAGE_START_STRING, out);
		fputs(TITLE_PREFIX, out);
		fputs(title_buffer, out);
		fputs(TITLE_POSTFIX, out);

		map<string, page_info>::iterator i;

		i = page_index.find( string(title_buffer) );

		if( i == page_index.end() ) {
			/* Copy old page */
			r = finish_page(in, out);
			if(r) {
				fprintf(stderr, "ERROR: unexpected end while copying page %s\n", title_buffer);
				return 1;
			}
			old_pages++;
		} else {
			/* Copy new page */
			i->second.replaced = true;

			FILE *new_in = fopen( i->second.path.c_str(), "r" );

			scan_to_title(new_in, title_buffer);

			finish_page(new_in, out);

			fclose(new_in);

			updated_pages++;
		}
	}

	/* Now include any new pages */

	map<string, page_info>::iterator i;
	for(i = page_index.begin(); i != page_index.end(); ++i) {
		if(i->second.replaced) continue;

		FILE *new_in = fopen( i->second.path.c_str(), "r" );

		scan_to_title(new_in, title_buffer);

		fputs(PAGE_START_STRING, out);
		fputs(TITLE_PREFIX, out);
		fputs(title_buffer, out);
		fputs(TITLE_POSTFIX, out);

		finish_page(new_in, out);

		fclose(new_in);

		new_pages++;
	}

	fputs(FINISH_STRING, out);

	fprintf(stderr, "%d updated pages\n", updated_pages);
	fprintf(stderr, "%d new pages\n", new_pages);
	fprintf(stderr, "%d unmodified pages\n", old_pages);

	return 0;
}

void syntax() {
	printf("RIFFLE, Update a MediaWiki dump from a list of exported pages\n");
	printf("SYNTAX: riffle -i input_file.xml -o output_file.xml -t path_to_pages\n");
	printf("\nWhere path_to_pages/ contains files like 0000, 0001, etc.\n");
	printf("\n\x1b[1mto riffle\x1b[0m v. To shuffle (playing cards) by holding part of a deck in each\nhand and raising up the edges before releasing them to fall alternately in\n one stack.\n");
}

int main(int argc, char **argv) {
	line_buffer = (char *) malloc(LINE_BUFFER_LEN*sizeof(*line_buffer));
	title_buffer = (char *) malloc(TITLE_BUFFER_LEN*sizeof(*title_buffer));

	char *inf = NULL;
	char *outf = NULL;
	char *trackpath = NULL;

	int opt;

	title_prefix_len = strlen(TITLE_PREFIX);

	while ((opt = getopt(argc, argv, "i:o:t:")) != -1) {
		switch (opt) {
			case 'i':
				inf = optarg;
				break;
			case 'o':
				outf = optarg;
				break;
			case 't':
				trackpath = optarg;
				break;
			case '?':
				syntax();
				exit(1);
		}
	}

	if(inf == NULL || outf == NULL || trackpath == NULL) {
		syntax();
		exit(1);
	}

	FILE *in = fopen(inf, "r");
	if(in == NULL) {
		fprintf(stderr, "ERROR: Can't open: %s\n", inf);
		exit(1);
	}
	FILE *out = fopen(outf, "w");
	if(out == NULL) {
		fprintf(stderr, "ERROR: Can't open: %s\n", outf);
		exit(1);
	}

	fprintf(stderr, "Scanning available updated pages...\n");

	int r = scan_chunks(trackpath);
	if(r) {
		exit(1);
	}

	fprintf(stderr, "Updating dump...\n");

	r = riffle_dump(in, out);
	if(r) {
		exit(1);
	}

	fclose(in);
	fclose(out);

	free(line_buffer);
	free(title_buffer);

	return 0;
}