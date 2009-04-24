# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Templates;

use strict;

use Exporter 'import';
use Hash::Util qw( lock_hash );
#use Text::Balanced;
use Regexp::Common;

use Wikiprep::Namespace qw( normalizeTitle normalizeNamespace isKnownNamespace );
use Wikiprep::ParserFunction qw( includeParserFunction );
use Wikiprep::nowiki qw( replaceTags extractTags );
use Wikiprep::Config;

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( %templates includeTemplates );

my $maxParameterRecursionLevels = 10;

# template bodies for insertion
our %templates;

if ($main::purePerl) {
  require Wikiprep::Templates::PurePerl;
} else {
  require Wikiprep::Templates::C;
}

sub prescan {
  my ($refToTitle, $refToId, $mwpage, $output) = @_;

  my $templateNamespace = $Wikiprep::Config::templateNamespace;
  if ($$refToTitle =~ /^$templateNamespace:/) {
    my $text = ${$mwpage->text};

    $output->newTemplate($$refToId, $$refToTitle);

    # We're storing template text for future inclusion, therefore,
    # remove all <noinclude> text and keep all <includeonly> text
    # (but eliminate <includeonly> tags per se).
    # However, if <onlyinclude> ... </onlyinclude> parts are present,
    # then only keep them and discard the rest of the template body.
    # This is because using <onlyinclude> on a text fragment is
    # equivalent to enclosing it in <includeonly> tags **AND**
    # enclosing all the rest of the template body in <noinclude> tags.
    # These definitions can easily span several lines, hence the "/s" modifiers.

    # Remove comments (<!-- ... -->) from template text. This is best done as early as possible so
    # that it doesn't slow down the rest of the code.
      
    # Note that comments must be removed before removing other XML tags,
    # because some comments appear inside other tags (e.g. "<span <!-- comment --> class=...>"). 
      
    # Comments can easily span several lines, so we use the "/s" modifier.

    $text =~ s/<!--.*?-->//sg;

    # Enable this to parse Uncyclopedia (<choose> ... </choose> is a
    # MediaWiki extension they use that selects random text - wikiprep
    # creates huge pages if we don't remove it)

    # $text =~ s/<choose[^>]*>(?:.*?)<\/choose[^>]*>/ /sg;

    my $onlyincludeAccumulator;
    while ($text =~ /<onlyinclude>(.*?)<\/onlyinclude>/sg) {
      my $onlyincludeFragment = $1;
      $onlyincludeAccumulator .= "$onlyincludeFragment\n";
    }
    if ( defined($onlyincludeAccumulator)) {
      $text = $onlyincludeAccumulator;
    } else {
      # If there are no <onlyinclude> fragments, simply eliminate
      # <noinclude> fragments and keep <includeonly> ones.
      $text =~ s/<noinclude\s*>.*?<\/noinclude\s*>/\n/sg;

      # In case there are unterminated <noinclude> tags
      $text =~ s/<noinclude\s*>.*$//sg;

      $text =~ s/<includeonly\s*>(.*?)<\/includeonly\s*>/$1/sg;

    }

    $templates{$$refToId} = $text;
  }
}

sub prescanFinished {
  lock_hash( %templates );

  my $numTemplates = scalar( keys(%templates) );
  LOG->notice("Loaded $numTemplates templates");
}

# Template parameter substitution

BEGIN {

my $paramRegex = qr/\{\{\{                              # Template parameter is enclosed in three braces
                                ( [^|{}]*               # Parameter name shouldn't contain braces (i.e.
                                                        # other unexpanded parameters)
                                  (?:
                                    \|                  # Optionally, the default value may be specified
                                                        # after a pipe symbol
                                                        
                                    (?:                 # Default value may contain
                                       [^{}]            #   a) some text without any braces or
                                       |
                                       $Regexp::Common::RE{balanced}{-parens => "{}"}

                                                        #   b) text that contains a balanced number of
                                                        #      open and close braces (i.e. unexpanded 
                                                        #      parameters, parser functions, templates, ...)
                                                        #
                                                        #      It's okay to have unexpanded parameters here
                                                        #      because they will be eventually expanded by
                                                        #      the loop in templateParameterRecursion()
                                    )*
                                  )?
                                )
                 \}\}\}/sx;

# Perform parameter substitution

# A parameter call ( {{{...}}} ) may span over a newline, hence the /s modifier

# Parameters may be nested, hence we do the substitution iteratively in a while loop. 
# We also limit the maximum number of iterations to avoid too long or even endless loops 
# (in case of malformed input).
    
# Parameters are nested because:
#   a) The default value is dependent on other parameters, e.g. {{{Author|{{{PublishYear|}}}}}} 
#      (here, the default value for 'Author' is dependent on 'PublishYear'). 
#
#   b) The parameter name is dependent on other parameters, e.g. {{{1{{{2|}}}|default}}}
#      (if second parameter to the template is "Foo", then this expands to "default" unless 
#      a parameter named "1Foo" is defined

# Additional complication is that the default value may contain parser function or
# template invocations (e.g. {{{1|{{#if:a|{{#if:b|c}}}}}}}. So to prevent improper 
# parsing we have to make sure that the default value contains properly balanced 
# braces.

sub templateParameterRecursion(\$\%) {
	my ($refToText, $refToParameterHash) = @_;

  my $parameterRecursionLevels = 0;

  my $substituteParameter = sub {
    my $parameter = $1;

    if ($parameter =~ /^([^|]*)\|(.*)$/) {
      # This parameter has a default value
      # my $paramName = $1;
      # my $defaultValue = $2;

      if ( exists($$refToParameterHash{$1}) ) {
        # use parameter value specified in template invocation
        return $$refToParameterHash{$1};  
      } else { # use the default value
        return $2;
      }
    } else {
      # parameter without a default value

      if ( exists($$refToParameterHash{$parameter}) ) {
        return $$refToParameterHash{$parameter};  # use parameter value specified in template invocation
      } else {
        # Parameter not specified in template invocation and does not have a default value -
        # do not perform substitution and keep the parameter in 3 braces
        # (these are Wiki rules for templates, see  http://meta.wikimedia.org/wiki/Help:Template ).

        # $result = "{{{$parameter}}}";

        # MediaWiki syntax indeed says that unspecified parameters should remain unexpanded, however in
        # practice we get a lot less noise in the output if we expand them to zero-length strings.
        return "";
      }
    }

    # Surplus parameters - i.e., those assigned values in template invocation but not used
    # in the template body - are simply ignored.
  };

  # We also require that the body of a parameter does not contain the paramet
  # (three successive opening braces - "\{\{\{"). We use negative lookahead t
  while ( ($parameterRecursionLevels < $maxParameterRecursionLevels) &&
           $$refToText =~ s/$paramRegex/$substituteParameter->()/gesx) {
      $parameterRecursionLevels++;
  }

  return $parameterRecursionLevels >= $maxParameterRecursionLevels;
}

}

# This function will further parse a template invocation # (e.g. everything within two braces {{ ... }}) 
# that has already been split into fields along |. It returns a hash of template parameters.

sub parseTemplateInvocation(\@\%) {
  my ($refToRawParameterList, $refToParameterHash) = @_;

  # Parameters can be either named or unnamed. In the latter case, their name is defined by their
  # ordinal position (1, 2, 3, ...).

  my $unnamedParameterCounter = 1;

  # It's legal for unnamed parameters to be skipped, in which case they will get default
  # values (if available) during actual instantiation. That is {{template_name|a||c}} means
  # parameter 1 gets the value 'a', parameter 2 value is not defined, and parameter 3 gets the value 'c'.
  # This case is correctly handled by function 'split', and does not require any special handling.
  foreach my $param (@$refToRawParameterList) {

    # Parameter values may contain "=" symbols, hence the parameter name extends up to
    # the first such symbol.
    
    # It is legal for a parameter to be specified several times, in which case the last assignment
    # takes precedence. Example: "{{t|a|b|c|2=B}}" is equivalent to "{{t|a|B|c}}".
    # Therefore, we don't check if the parameter has been assigned a value before, because
    # anyway the last assignment should override any previous ones.
    my ( $parameterName, $parameterValue ) = split(/\s*=\s*/, $param, 2);

    # $parameterName is undefined if $param is an empty string
    if( not defined( $parameterName ) ) {
      $parameterName = "";
    }

    if( defined( $parameterValue ) ) {
      # This is a named parameter.
      # This case also handles parameter assignments like "2=xxx", where the number of an unnamed
      # parameter ("2") is specified explicitly - this is handled transparently.
      $$refToParameterHash{$parameterName} = $parameterValue;
    } else {
      # this is an unnamed parameter
      $$refToParameterHash{$unnamedParameterCounter} = $param;

      $unnamedParameterCounter++;
    }
  }
}

sub includeTemplateText(\$\%\%\$$) {
  my ($refToTemplateTitle, $refToParameterHash, $page, $refToResult) = @_;

  my $includedPageId = &Wikiprep::Link::resolveLink($refToTemplateTitle);

  if ( defined($includedPageId) && exists($templates{$includedPageId}) ) {

    # Log which template has been included in which page with which parameters
    my $templates = $page->{templates};
  
    $templates->{$includedPageId} = [] unless( defined( $templates->{$includedPageId} ) );

    push( @{$templates->{$includedPageId}}, $refToParameterHash );

    # OK, perform the actual inclusion with parameter substitution. 

    # First we retrieve the text of the template
    $$refToResult = $templates{$includedPageId};

    # Substitute template parameters
    if( &templateParameterRecursion($refToResult, $refToParameterHash) ) {
      LOG->info("maximum template parameter recursion level reached");
    }

  } else {
    # The page being included cannot be identified - perhaps we skipped it (because currently
    # we only allow for inclusion of pages in the Template namespace), or perhaps it's
    # a variable name like {{NUMBEROFARTICLES}}. Just remove this inclusion directive and
    # replace it with a space
    LOG->info("template '$$refToTemplateTitle' is not available for inclusion");
    $$refToResult = " ";
  }
}

sub instantiateTemplate {
  my ($refToTemplateInvocation, $page, $templateRecursionLevel) = @_;

  if( length($$refToTemplateInvocation) > 32767 ) {
    # Some {{#switch ... }} statements are excesivelly long and usually do not produce anything
    # useful. Plus they can cause segfauls in older versions of Perl.

    LOG->info("ignoring long template invocation: ", $refToTemplateInvocation);
    return "";
  }

  LOG->debug("template recursion level ", $templateRecursionLevel);
  LOG->debug("instantiating template: ", $refToTemplateInvocation);

  # The template name extends up to the first pipeline symbol (if any).
  # Template parameters go after the "|" symbol.
  
  # Template parameters often contain URLs, internal links, or just other useful text,
  # whereas the template serves for presenting it in some nice way.
  # Parameters are separated by "|" symbols. However, we cannot simply split the string
  # on "|" symbols, since these frequently appear inside internal links. Therefore, we split
  # on those "|" symbols that are not inside [[...]]. 
      
  # Note that template name can also contain internal links (for example when template is a
  # parser function: "{{#if:[[...|...]]|...}}". So we use the same mechanism for splitting out
  # the name of the template as for template parameters.
  
  # Same goes if template parameters include other template invocations.

  # We also trim leading and trailing whitespace from parameter values.
  
  my ($templateTitle, @rawTemplateParams) = &splitTemplateInvocation($$refToTemplateInvocation);

  return "" unless defined $templateTitle;
  
  # We now have the invocation string split up on | in the @rawTemplateParams list.
  # String before the first "|" symbol is the title of the template and is stored in
  # $templateTitle.
  
  &includeTemplates($page, \$templateTitle, $templateRecursionLevel + 1);

  my $result = &includeParserFunction(\$templateTitle, \@rawTemplateParams, $page, $templateRecursionLevel);

  # If this wasn't a parser function call, try to include a template.
  if ( not defined($result) ) {
    &normalizeTitle(\$templateTitle, $Wikiprep::Config::templateNamespace);

    if(exists $Wikiprep::Config::overrideTemplates{$templateTitle}) {
      LOG->info("overriding template: ", $templateTitle);
      return $Wikiprep::Config::overrideTemplates{$templateTitle};
    }
  
    my %templateParams;
    &parseTemplateInvocation(\@rawTemplateParams, \%templateParams);

    &includeTemplateText(\$templateTitle, \%templateParams, $page, \$result);
  }

  &includeTemplates($page, \$result, $templateRecursionLevel + 1);

  return $result;  # return value
}

my $nowikiRegex = qr/(<\s*nowiki[^<>]*>.*?<\s*\/nowiki[^<>]*>)/s;
my $preRegex = qr/(<\s*pre[^<>]*>.*?<\s*\/pre[^<>]*>)/s;

# This function transcludes all templates in a given string and returns a fully expanded
# text. 

# It's called recursively, so we have a $templateRecursionLevel parameter to track the 
# recursion depth and break out in case it gets too deep.

sub includeTemplates {
  my ($page, $refToText, $templateRecursionLevel) = @_;

  return unless $$refToText =~ /\{/;

  if( $templateRecursionLevel > $Wikiprep::Config::maxTemplateRecursionLevels ) {

    # Ignore this template if limit is reached 

    # Since we limit the number of levels of template recursion, we might end up with several
    # un-instantiated templates. In this case we simply eliminate them - however, we do so
    # later, in function 'postprocessText()', after extracting categories, links and URLs.

    LOG->info("maximum template recursion level reached");
    return " ";
  }

  # Templates are frequently nested. Occasionally, parsing mistakes may cause template insertion
  # to enter an infinite loop, for instance when trying to instantiate Template:Country
  # {{country_{{{1}}}|{{{2}}}|{{{2}}}|size={{{size|}}}|name={{{name|}}}}}
  # which is repeatedly trying to insert template "country_", which is again resolved to
  # Template:Country. The straightforward solution of keeping track of templates that were
  # already inserted for the current article would not work, because the same template
  # may legally be used more than once, with different parameters in different parts of
  # the article. Therefore, we simply limit the number of iterations of nested template
  # inclusion.

  # Note that this isn't equivalent to MediaWiki handling of template loops 
  # (see http://meta.wikimedia.org/wiki/Help:Template), but it seems to be working well enough for us.
  
  my %nowikiChunksReplaced;
  my %preChunksReplaced;

  # Hide template invocations nested inside <nowiki> tags from the s/// operator. This prevents 
  # infinite loops if templates include an example invocation in <nowiki> tags.

  &extractTags(\$preRegex, $refToText, \%preChunksReplaced);
  &extractTags(\$nowikiRegex, $refToText, \%nowikiChunksReplaced);

  my $invocation = 0;
  my $new_text = "";

  for my $token ( &splitOnTemplates($$refToText) ) {
    if( $invocation ) {
      $new_text .= &instantiateTemplate(\$token, $page, $templateRecursionLevel);
      $invocation = 0;
    } else {
      $new_text .= $token;
      $invocation = 1;
    }
  }

  $$refToText = $new_text;

  # $text =~ s/$templateRegex/&instantiateTemplate($1, $refToId, $refToTitle, $templateRecursionLevel)/segx;

  &replaceTags($refToText, \%nowikiChunksReplaced);
  &replaceTags($refToText, \%preChunksReplaced);

  # print LOGF "Finished with templates level $templateRecursionLevel\n";
  # print LOGF "#########\n\n";
  # print LOGF "$text";
  # print LOGF "#########\n\n";
  
  my $text_len = length $new_text;
  LOG->debug("text length after templates level ", $templateRecursionLevel, ": ", $text_len, " bytes");
}

1;
