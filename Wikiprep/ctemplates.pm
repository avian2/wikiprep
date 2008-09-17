
package Wikiprep::ctemplates;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( splitOnTemplates splitTemplateInvocation );

# This module provides C implementation of two functions
# (original Perl implementations can be found in templates.pm)
#
# splitOnTemplates() - splits a string on template invocations
#
# This function splits a string containing Wiki text into a
# " text - template invocation - text - template invocation - text ... "
# list of strings. Where "text" is ordinary text and "template invocation"
# is contents of "{{ ... }}" blocks. Such blocks may contain other nested
# "{" constructs.
#
# splitTemplateInvocation() - splits a string on "|" symbols
#
# This function splits template invocations (for example as returned by
# splitOnTemplates() ) into separate template parameters.
#
# It basically splits the string on "|" symbols, so that each split string
# contains balanced "{" or "[" constructs. This for example means that
# it will correctly split template parameters even when they contain links
# or other template invocations (that themselves contain "|" symbols)

# use Inline C => Config => OPTIMIZE => '-g';
use Inline C => <<'END_C';
void splitOnTemplates(SV *svi) {

	char *input = SvPV_nolen(svi);
	SV *sv;

	Inline_Stack_Vars;
	Inline_Stack_Reset;

	if( *input == '\0' ) {
		/* Nothing to be done for an empty string */
		sv = sv_2mortal( newSVpvn("", 0) );
		if( SvUTF8( svi ) ) SvUTF8_on(sv);
		Inline_Stack_Push( sv );
		Inline_Stack_Done;
		return;
	}

	/* Start one character inside the string */
	char *cur = &input[1];
	char *prev = cur - 1;

	char *template_start;

	char *text_start = input;
	char *text_end;

	unsigned int depth = 0;

	while(1) {
		/* Search for a template start marker */
			
		while( !( *prev == '{' && *cur == '{' ) ) {
			if( *cur == '\0' ) goto end;

			prev = cur;
			cur++;
		}

		/* ___{{____}}___       
		 *     ^- cur
		 * ^----- text_start
		 */

		template_start = cur + 1;

		while( !( *prev == '}' && *cur == '}' && depth == 0 ) ) {
			switch(*cur) {
				case '\0': 
					goto end;
					break;
				case '{':
					depth++;
					break;
				case '}':
					if (depth > 0) depth--;
					break;
			}
					
			prev = cur;
			cur++;
		}

		text_end = template_start - 2;

		/* ___{{____}}___       
		 * ^  ^ ^    ^- cur
		 * |  |  ------ template_start
		 * |   -------- text_end
		 *  ----------- text_start
		 */

		*text_end = '\0';
		sv = sv_2mortal( newSVpvn(text_start, text_end - text_start ) );
		if( SvUTF8( svi ) ) SvUTF8_on(sv);
		Inline_Stack_Push( sv );
		*text_end = '{';

		*prev = '\0';
		sv = sv_2mortal( newSVpvn(template_start, prev - template_start) );
		if( SvUTF8( svi ) ) SvUTF8_on(sv);
		Inline_Stack_Push( sv );
		*prev = '}';

		text_start = cur + 1;
	}

	end:

	sv = sv_2mortal( newSVpvn(text_start, cur - text_start ) );
	if( SvUTF8( svi ) ) SvUTF8_on(sv);
	Inline_Stack_Push( sv );

	Inline_Stack_Done;
}

void splitTemplateInvocation(SV *svi) 
{
	char *input = SvPV_nolen(svi);
	SV *sv;

	Inline_Stack_Vars;
	Inline_Stack_Reset;

	if( *input == '\0' ) {
		/* Nothing to be done for an empty string */
		Inline_Stack_Done;
		return;
	}

	unsigned int brace = 0;
	unsigned int square = 0;

	char *cur = input;
	char *param_start = cur;

	while(1) {
		switch(*cur) {
			case '\0':
				goto end2;
				break;
			case '|':
				if(brace == 0 && square == 0) {
					*cur = '\0';
					sv = sv_2mortal( newSVpvn(param_start, cur - param_start) );
					if( SvUTF8( svi ) ) SvUTF8_on(sv);
					Inline_Stack_Push( sv );
					*cur = '|';

					param_start = cur + 1;
				}
				break;
			case '{':
				brace++;
				break;
			case '}':
				if( brace > 0) brace --;
				break;
			case '[':
				square++;
				break;
			case ']':
				if( square > 0) square--;
				break;
		}

		cur++;
	}

	end2:

	sv = sv_2mortal( newSVpvn(param_start, cur - param_start) );
	if( SvUTF8( svi ) ) SvUTF8_on(sv);
	Inline_Stack_Push( sv );

	Inline_Stack_Done;
}

END_C

1
