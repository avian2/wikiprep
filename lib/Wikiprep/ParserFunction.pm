# vim:sw=2:tabstop=2:expandtab

package Wikiprep::ParserFunction;

use strict;
use warnings;

use Exporter 'import';

use Wikiprep::Namespace qw( normalizeNamespaceTitle );
use Wikiprep::languages qw( languageName );
use Wikiprep::Config;

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( includeParserFunction );

# Magic words behave like built-in templates that take no parameters.

# {{FULLPAGENAME}} returns full name of the page (including the 
# namespace prefix. {{PAGENAME}} returns only the title.

sub magicPagename {
  my ($page) = @_;

  # FIXME: This is slow - consider making a specialized function for
  # splitting off namespace when the title is already normalized.
  my ($namespace, $title) = &normalizeNamespaceTitle($page->{title});
  return $title;
}

my %magicWords = (

  # {{pagename}} returns the name of the current page. 
  # Only capitalizations below work.

  'pagename' => \&magicPagename,
  'Pagename' => \&magicPagename,
  'PAGENAME' => \&magicPagename,

  'NAMESPACE' => sub {
                  my ($page) = @_;

                  my ($namespace, $title) = &normalizeNamespaceTitle($page->{title}, '');
                  return $namespace;
                },

  'FULLPAGENAME' => sub {
                  my ($page) = @_;
                  return $page->{title};
                },

  # Extra 'E' means the result is URL encoded. 
  
  'PAGENAMEE' => sub {
                  my ($page) = @_;

                  my ($namespace, $title) = &normalizeNamespaceTitle($page->{title});
                  $title =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
                  return $title;
                },

  'FULLPAGENAMEE' => sub {
                  my ($page) = @_;

                  my $result = $page->{title};
                  $result =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
                  return $result;
                },

  'SERVER' => sub {
                  return "http://wikiprep.example.com";
                },
);

my %parserFunctions = (

	'#if'	=> sub {
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
  '#ifeq' => sub {
                # lvalue has templates expanded.
                my ($page, $templateRecursionLevel, $lvalue, $rvalue, $valueIfTrue, $valueIfFalse) = @_;

                if ( defined($rvalue ) ) {
                  &Wikiprep::Templates::includeTemplates($page, \$rvalue, $templateRecursionLevel + 1)
                    if $rvalue =~ /\{/;

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

 '#switch' => sub {
              my ($page, $templateRecursionLevel, @parameterList) = @_; 

              # Code ported from ParserFunctions.php
              # Documentation at http://www.mediawiki.org/wiki/Help:Extension:ParserFunctions#.23switch:

              my $primary = shift( @parameterList );

              my $lvalue;
              my $rvalue;
              my $found;
              my $default;

              for my $param (@parameterList) {
                ($lvalue, $rvalue) = split(/\s*=\s*/, $param, 2);
                if( defined $rvalue ) {
                  &Wikiprep::Templates::includeTemplates($page, \$lvalue, $templateRecursionLevel + 1)
                    if $lvalue =~ /\{/;
                  # Found "="
                  if( $found || $lvalue eq $primary ) {
                    # Found a match, return now
                    return $rvalue;
                  } elsif( $lvalue =~ /^#default/ ) {
                    $default = $rvalue;
                  } 
                  # else wrong case, continue
                } elsif( defined $lvalue ) {
                  &Wikiprep::Templates::includeTemplates($page, \$lvalue, $templateRecursionLevel + 1)
                    if $lvalue =~ /\{/;
                  # Multiple input, single output
                  # If the value matches, set a flag and continue
                  if( $lvalue eq $primary ) {
                    $found = 1;
                  }
                }
              }
              # Default case
              # Check if the last item had no = sign, thus specifying the default case
              if( !$rvalue ) {
                return $lvalue;
              } elsif( $default ) {
                return $default;
              } else {
                return '';
              }
            },

  '#language' => sub {
              # {{#language: code}} gives the language name of selected RFC 3066 language codes, 
              # otherwise it returns the input value as is.

              my ($page, $templateRecursionLevel, $langCode) = @_;
              return &languageName($langCode) || '';
            },

  'urlencode' => sub {
              # This function is used in some pages to construct links
              # http://meta.wikimedia.org/wiki/Help:URL
              
              my ($page, $templateRecursionLevel, $string) = @_;

              LOG->debug("URL encoding string: " . $string);

              $string =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
              return $string;
            },

  'lc' => sub {
              my ($page, $templateRecursionLevel, $string) = @_;

              return lc($string);
            },

  'ucfirst' => sub {
              my ($page, $templateRecursionLevel, $string) = @_;

              return ucfirst($string);
            },

  'int' => sub {
              my ($page, $templateRecursionLevel, $string) = @_;

              if ($string eq 'Lang') {
                return $Wikiprep::Config::intLang;
              } else {
                return $string;
              }
            },
);

sub includeParserFunction(\$\%\%$\$) {
  my ($refToTemplateTitle, $refToRawParameterList, $page, $templateRecursionLevel) = @_;

  # Parser functions have the same syntax as templates, except their names start with a hash
  # and end with a colon. Everything after the first colon is the first argument.

  # Parser function invocation can span more than one line, hence the /s modifier

  # http://meta.wikimedia.org/wiki/Help:ParserFunctions
  
  if ( $$refToTemplateTitle =~ /^(#?[a-z]+):\s*(.*?)\s*$/s ) {
    my $functionName = $1;

    LOG->debug("evaluating parser function " . $functionName);

    if( exists($parserFunctions{$functionName}) ) {

      my $firstParam = $2;

      &Wikiprep::Templates::includeTemplates($page, \$firstParam, $templateRecursionLevel + 1)
        if $firstParam =~ /\{/;

      return $parserFunctions{$functionName}->($page, $templateRecursionLevel, 
                                               $firstParam, @$refToRawParameterList);
    } else {
      LOG->info("function " . $functionName . " not supported");

      # Unknown function -- fall back by inserting first argument, if available. This seems
      # to be the most sensible alternative in most cases (for example in #time and #date)

      if ( exists($$refToRawParameterList[0]) ) {
        return $$refToRawParameterList[0];
      } else {
        return "";
      }
    }

    # print LOGF "Function returned: $result\n";

  } elsif( exists($magicWords{$$refToTemplateTitle}) ) {
    return $magicWords{$$refToTemplateTitle}->($page);
  } else {
    return undef;
  }
}

1;
