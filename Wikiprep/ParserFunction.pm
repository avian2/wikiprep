# vim:sw=2:tabstop=2:expandtab

package Wikiprep::ParserFunction;

use strict;
use warnings;

use Exporter 'import';

use Wikiprep::languages qw( languageName );

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( includeParserFunction );

my %parserFunctions = (

	'if'	=>  sub {
          				my ($page, $templateRecursionLevel, $testValue, $valueIfTrue, $valueIfFalse) = @_;

                  if ( length($testValue) > 0 ) {
                    # The {{#if:}} function is an if-then-else construct. The applied condition is 
                    # "The condition string is non-empty". 

                    if ( defined($valueIfTrue) && ( length($valueIfTrue) > 0 ) ) {
                      return $valueIfTrue;
                    } else {
                      return "";
                    }
                  } else {
                    if ( defined($valueIfFalse) && ( length($valueIfFalse) > 0 ) ) {
                      return $valueIfFalse;
                    } else {
                      return "";
                    }
                  }
                },
  'ifeq'  => sub {
                # lvalue has templates expanded.
                my ($page, $templateRecursionLevel, $lvalue, $rvalue, $valueIfTrue, $valueIfFalse) = @_;

                if ( defined($rvalue ) ) {
                  &Wikiprep::Templates::includeTemplates($page, \$rvalue, $templateRecursionLevel + 1);

                  # lvalue is always defined
                  if ( $lvalue eq $rvalue ) {
                    # The {{#ifeq:}} function is an if-then-else construct. The applied condition is 
                    # "is rvalue equal to lvalue". Note that this does only string comparison while 
                    # MediaWiki implementation also supports numerical comparissons.

                    if ( defined($valueIfTrue) && ( length($valueIfTrue) > 0 ) ) {
                      return $valueIfTrue;
                    } else {
                      return "";
                    }
                  } else {
                    if ( defined($valueIfFalse) && ( length($valueIfFalse) > 0 ) ) {
                      return $valueIfFalse;
                    } else {
                        return "";
                    }
                  }
                } else {
                  return "";
                }
              },

 'switch' => sub {
              my ($page, $templateRecursionLevel, @parameterList) = @_; 

              # Code ported from ParserFunctions.php
              # Documentation at http://www.mediawiki.org/wiki/Help:Extension:ParserFunctions#.23switch:

              my $primary = shift( @parameterList );

              my @parts;
              my $found;
              my $default;

              for my $param (@parameterList) {
                @parts = split(/\s*=\s*/, $param, 2);
                if( $#parts == 1 ) {
                  my $lvalue = $parts[0];
                  &Wikiprep::Templates::includeTemplates($page, \$lvalue, $templateRecursionLevel + 1);
                  # Found "="
                  if( $found || $lvalue eq $primary ) {
                    # Found a match, return now
                    return $parts[1];
                  } elsif( $parts[0] =~ /^#default/ ) {
                    $default = $parts[1];
                  } 
                  # else wrong case, continue
                } elsif( $#parts == 0 ) {
                  my $lvalue = $parts[0];
                  &Wikiprep::Templates::includeTemplates($page, \$lvalue, $templateRecursionLevel + 1);
                  # Multiple input, single output
                  # If the value matches, set a flag and continue
                  if( $lvalue eq $primary ) {
                    $found = 1;
                  }
                }
              }
              # Default case
              # Check if the last item had no = sign, thus specifying the default case
              if( $#parts == 0 ) {
                return $parts[0];
              } elsif( $default ) {
                return $default;
              } else {
                return '';
              }
            },

  language => sub {
              # {{#language: code}} gives the language name of selected RFC 3066 language codes, 
              # otherwise it returns the input value as is.

              my ($page, $templateRecursionLevel, $langCode) = @_;
              return &languageName($langCode) || '';
            },
);

sub includeParserFunction(\$\%\%$\$) {
  my ($refToTemplateTitle, $refToRawParameterList, $page, $templateRecursionLevel) = @_;

  # Parser functions have the same syntax as templates, except their names start with a hash
  # and end with a colon. Everything after the first colon is the first argument.

  # Parser function invocation can span more than one line, hence the /s modifier

  # http://meta.wikimedia.org/wiki/Help:ParserFunctions
  
  if ( $$refToTemplateTitle =~ /^\#([a-z]+):\s*(.*?)\s*$/s ) {
    my $functionName = $1;
    my $firstParam = $2;
    &Wikiprep::Templates::includeTemplates($page, \$firstParam, $templateRecursionLevel + 1);

    unshift( @$refToRawParameterList, $firstParam );

    LOG->debug("evaluating parser function #", $functionName);

    my $func = $parserFunctions{$functionName};

    if( $func ) {
      return &$func($page, $templateRecursionLevel, @$refToRawParameterList);
    } else {
      LOG->info("function #$functionName not supported");

      # Unknown function -- fall back by inserting first argument, if available. This seems
      # to be the most sensible alternative in most cases (for example in #time and #date)

      if ( exists($$refToRawParameterList[1]) && ( length($$refToRawParameterList[1]) > 0 ) ) {
        return $$refToRawParameterList[1];
      } else {
        return "";
      }
    }

    # print LOGF "Function returned: $result\n";

  } elsif ( $$refToTemplateTitle =~ /^urlencode:\s*(.*)/ ) {
    # This function is used in some pages to construct links
    # http://meta.wikimedia.org/wiki/Help:URL

    my $result = $1;
    LOG->debug("URL encoding string: ", $result);

    $result =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;

    return $result;
  } elsif ( lc $$refToTemplateTitle eq "pagename" ) {
    # FIXME: {{FULLPAGENAME}} returns full name of the page (including the 
    # namespace prefix. {{PAGENAME}} returns only the title.
    #
    # Also consider supporting {{SERVER}}, which is used to construct edit
    # links in some stub templates (external URLs aren't removed properly
    # without it)
    return $page->{title};
  }

  return undef;
}

1;
