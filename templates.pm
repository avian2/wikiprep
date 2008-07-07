# vim:sw=2:tabstop=2:expandtab

use strict;
use File::Path;
#use Text::Balanced;
use Regexp::Common;
use utils;

use ctemplates;

package templates;

my $maxParameterRecursionLevels = 10;


# Template logging functions

sub prepare(\$) {
  my ($refToTemplateIncDir) = @_;

  mkdir($$refToTemplateIncDir);

  my $n = 1;
  do {
    my $path = "$$refToTemplateIncDir/$n";
    if( -d $path ) {
      File::Path::rmtree($path, 0, 0);
    }
    mkdir("$$refToTemplateIncDir/$n");
    $n++;
  } while($n < 10);
}

sub logPath(\$\$) {
  my ($refToTemplateIncDir, $refToTemplateId) = @_;

  my $prefix = substr($$refToTemplateId, 0, 1);

  return "$$refToTemplateIncDir/$prefix/$$refToTemplateId";
}


# Template parameter substitution

sub substituteParameter($\%) {
  my ($parameter, $refToParameterHash) = @_;

  my $result;

  if ($parameter =~ /^([^|]*)\|(.*)$/) {
    # This parameter has a default value
    my $paramName = $1;
    my $defaultValue = $2;

    if ( defined($$refToParameterHash{$paramName}) ) {
      $result = $$refToParameterHash{$paramName};  # use parameter value specified in template invocation
    } else { # use the default value
      $result = $defaultValue;
    }
  } else {
    # parameter without a default value

    if ( defined($$refToParameterHash{$parameter}) ) {
      $result = $$refToParameterHash{$parameter};  # use parameter value specified in template invocation
    } else {
      # Parameter not specified in template invocation and does not have a default value -
      # do not perform substitution and keep the parameter in 3 braces
      # (these are Wiki rules for templates, see  http://meta.wikimedia.org/wiki/Help:Template ).

      # $result = "{{{$parameter}}}";

      # MediaWiki syntax indeed says that unspecified parameters should remain unexpanded, however in
      # practice we get a lot less noise in the output if we expand them to zero-length strings.
      $result = "";
    }
  }

  # Surplus parameters - i.e., those assigned values in template invocation but not used
  # in the template body - are simply ignored.

  $result;  # return value
}

BEGIN {

my $paramRegex = qr/\{\{\{                              # Template parameter is enclosed in three braces
                                ( [^{}]*                # Parameter name shouldn't contain braces (i.e.
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

sub templateParameterRecursion(\$\$$) {
	my ($refToText, $refToParameterHash, $parameterRecursionLevel) = @_;

  my $parameterRecursionLevels = 0;
 
  # We also require that the body of a parameter does not contain the paramet
  # (three successive opening braces - "\{\{\{"). We use negative lookahead t
  while ( ($parameterRecursionLevels < $maxParameterRecursionLevels) &&
           $$refToText =~ s/$paramRegex/&substituteParameter($1, $refToParameterHash)/gesx) {
      $parameterRecursionLevels++;
  }

  if($parameterRecursionLevels >= $maxParameterRecursionLevels) {
    return 1
  } else {
    return 0
  }
}

}

# Template call parsing

sub splitTemplateInvocationFast($) {

  my ($refToTemplateInvocation) = @_;

  return split(/\|/, $$refToTemplateInvocation);
}

sub splitTemplateInvocationSlow($) {

  my ($refToTemplateInvocation) = @_;

  # This is a simple parser that splits the invocation string on those "|" symbols that are not
  # nested within "[" or "{" braces.
  
  # We first split the string into tokens - symbols we care about and other text.

  my $brace = 0;
  my $square = 0;
  my $accumulator = "";
  my @parameters = ();

  # Iterate through tokens and gather them into the accumulator

  my $token;
  for $token ( split(/([\{\}\[\]\|])/, $$refToTemplateInvocation ) ) {
    if( $token eq '|' and $brace == 0 and $square == 0 ) {

      # Unnested "|" means we store the contents of the accumulator into a new parameter

      push(@parameters, $accumulator);
      $accumulator = "";
    } else {
      if( $token eq '{' ) {
        $brace ++;
      } elsif( $token eq '}' ) {
        $brace -- if $brace > 0;
      } elsif( $token eq '[' ) {
        $square ++;
      } elsif( $token eq ']' ) {
        $square -- if $square > 0;
      }
      $accumulator .= $token;
    }
  }
  push(@parameters, $accumulator);

  return @parameters;
}

sub splitTemplateInvocation($) {
  my $templateInvocation = shift;

  if( $templateInvocation =~ /[\{\[]/ ) {
    return splitTemplateInvocationSlow(\$templateInvocation);
  } else {
    return splitTemplateInvocationFast(\$templateInvocation);
  }
}

# This function will parse a template invocation (e.g. everything within two braces {{ ... }})
# and return a template title and a hash of template parameters.

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

sub parseTemplateInvocation(\$\$\%) {
  my ($refToTemplateInvocation, $refToTemplateTitle, $refToParameterHash) = @_;

  #my @parameters = &splitTemplateInvocation($$refToTemplateInvocation);
  my @parameters = &ctemplates::splitTemplateInvocation($$refToTemplateInvocation);

  # We now have the invocation string split up in the @parameters list.

  # String before the first "|" symbol is the title of the template.
  $$refToTemplateTitle = shift(@parameters);

  # Template invocation does not contain any parameters
  return unless($#parameters > -1);

  # Parameters can be either named or unnamed. In the latter case, their name is defined by their
  # ordinal position (1, 2, 3, ...).

  my $unnamedParameterCounter = 0;
  my $parameterCounter = 0;

  # It's legal for unnamed parameters to be skipped, in which case they will get default
  # values (if available) during actual instantiation. That is {{template_name|a||c}} means
  # parameter 1 gets the value 'a', parameter 2 value is not defined, and parameter 3 gets the value 'c'.
  # This case is correctly handled by function 'split', and does not require any special handling.
  my $param;
  foreach $param (@parameters) {

    # if the value does not contain a link, we can later trim whitespace
    my $doesNotContainLink = ($param !~ /\]\]/);

    # For parser functions we need unmodified parameters by position. For example:
    # "{{#if: true | id=xxx }}" must expand to "id=xxx". So we store raw parameter values in parameter 
    # hash. Note that the key of the hash can't be generated any other way (parameter names can't 
    # include '=' characters)
    $parameterCounter++;

    if ($doesNotContainLink) {
      $param =~ s/^\s+//;
      $param =~ s/\s+$//;
    } 

    $$refToParameterHash{"=${parameterCounter}="} = $param;

    # Spaces before or after a parameter value are normally ignored, UNLESS the parameter contains
    # a link (to prevent possible gluing the link to the following text after template substitution)

    # Parameter values may contain "=" symbols, hence the parameter name extends up to
    # the first such symbol.
    # It is legal for a parameter to be specified several times, in which case the last assignment
    # takes precedence. Example: "{{t|a|b|c|2=B}}" is equivalent to "{{t|a|B|c}}".
    # Therefore, we don't check if the parameter has been assigned a value before, because
    # anyway the last assignment should override any previous ones.
    my ( $parameterName, $parameterValue ) = split(/=/, $param, 2);

    if( defined( $parameterName ) ) {
      if( defined( $parameterValue ) ) {
        # This is a named parameter.
        # This case also handles parameter assignments like "2=xxx", where the number of an unnamed
        # parameter ("2") is specified explicitly - this is handled transparently.

        $parameterName =~ s/\s+$//;
      
        # if the value does not contain a link, trim whitespace
        if ($doesNotContainLink) {
          $parameterValue =~ s/^\s+//;
        } else {
          $parameterName =~ s/^\s+//;
        }

        $$refToParameterHash{$parameterName} = $parameterValue;
      } else {
        # this is an unnamed parameter
        $unnamedParameterCounter++;

        $$refToParameterHash{$unnamedParameterCounter} = $param;
      }
    }
  }
}

BEGIN {

# Regular expression that matches a template include directive. It is replaced with fully
# expanded template text in includeTemplates() below.

# Matches two opening braces with any balanced combination of braces within. Note that this also
# matches for example {{{3}}} (which can happen if we get an unexpanded template parameter in the
# output). This case is handled as an unknown template, which is then replaced by an empty string.

# (some pages have template parameters in them although they are not templates)

my $templateRegex = qr/(\{$Regexp::Common::RE{balanced}{-parens => "{}"}\})/s;

sub splitOnTemplates($) {
  my $text = shift;

  my @retval;
  my $invocation = 0;

  for my $i ( split(/$templateRegex/s, $text) ) {
    if( $invocation ) {
      $i =~ s/^\{\{//;
      $i =~ s/\}\}$//;
      $invocation = 0;
    } else {
      $invocation = 1;
    }
    push(@retval, $i);
  }

  return @retval;
}

}

1
