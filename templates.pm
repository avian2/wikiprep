# vim:sw=2:tabstop=2:expandtab

use strict;
use File::Path;
#use Text::Balanced;
use Regexp::Common;

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

## my $balancedExtractFunctions = [ Text::Balanced::gen_extract_tagged( '\{', '\}', '' ) ];
#my $balancedExtractFunctions = [ sub { Text::Balanced::extract_bracketed($_[0], '{}', '') } ];

#sub templateParameterRecursion(\$\$$) {
#	my ($refToText, $refToParameterHash, $parameterRecursionLevel) = @_;
#
#  return unless ($$refToText =~ /[{}]/);
#
#	my @splitText = Text::Balanced::extract_multiple($$refToText, $balancedExtractFunctions );
#
#	for my $piece (@splitText) {
#		if($piece =~ /^\{\{\{(.*)\}\}\}$/s) {
#			$piece = &substituteParameter($1, $refToParameterHash);
#
#  	  &templateParameterRecursion(\$piece, $refToParameterHash, $parameterRecursionLevel + 1);
#		} elsif($piece =~ /^\{\{(.*)\}\}$/s) {
#			my $work = $1;
#
#		  &templateParameterRecursion(\$work, $refToParameterHash, $parameterRecursionLevel + 1);
#
#			$piece = "{{$work}}";
#
#    } else {
#			my $back = chop($piece);
#
#			if($back eq '}') {
#				&templateParameterRecursion(\$piece, $refToParameterHash, $parameterRecursionLevel + 1);
#			}
#
#			$piece = $piece . $back;
#		}
#	}
#
#	$$refToText = join('', @splitText);
#}

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

1
