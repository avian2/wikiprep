use Benchmark 'cmpthese';
use Wikiprep::templates;
use ctemplates;

$text = <<'END';
{{ infobox
| bodyclass  = biography vcard
| bodystyle  = width:{{#if:{{{box_width|}}}|{{{box_width}}} |22em}}; font-size:95%; text-align:left;
| above      = '''{{{name|{{PAGENAME}}}}}'''
| aboveclass = fn
| abovestyle = text-align:center; font-size:125%;
| image      = {{#if:{{{image|}}}|[[Image:{{{image}}}|{{#if:{{{image_size|{{{imagesize|}}}}}}|{{{image_size|{{{imagesize}}}}}}|225px}}]]}}
| imageclass = {{image class names|{{{image}}}}}
| imagestyle = padding:4pt; line-height:1.25em; text-align:center; font-size:8pt;
| caption    = <div style="padding-top:2pt;">{{{caption|}}}</div>
| labelstyle = padding:0.2em 1.0em 0.2em 0.2em; background:transparent; line-height:1.2em; text-align:left; font-size:90%;
| datastyle  = padding:0.2em; line-height:1.3em; vertical-align:middle; font-size:90%;

| label1     = {{#if:{{{birth_name|}}}{{{birth_date|}}}{{{birth_place|}}}|Born}}
| data1      = {{#if:{{{birth_name|}}}|{{{birth_name}}}<br />}}{{#if:{{{birth_date|}}} |{{{birth_date}}}<br />}}{{{birth_place|}}}
| label2     = {{#if:{{{death_date|}}}{{{death_place|}}}|Died }}
| data2      = {{#if:{{{death_date|}}}|{{{death_date}}}<br />}}{{{death_place|}}}
| label3     = Cause&nbsp;of death
| data3      = {{{death_cause|}}}
| label4     = Burial&nbsp;place
| class4     = label
| data4      = {{{resting_place|}}}{{#if:{{{resting_place_coordinates|}}}|<br />{{{resting_place_coordinates}}} }}
| label5     = Residence
| class5     = label
| data5      = {{{residence|}}}
| label6     = Nationality
| data6      = {{{nationality|}}}
| label7     = Other&nbsp;names
| class7     = nickname
| data7      = {{{other_names|}}}
| label8     = Education
| data8      = {{{education|}}}
| label9     = Alma&nbsp;mater
| data9      = {{{alma_mater|}}}
| label10    = Occupation
| data10     = {{{occupation|}}}
| label11    = Employers
| data11     = {{{employer|}}}
| label12    = Home&nbsp;town
| data12     = {{{home_town|}}}
| label13    = Title
| data13     = {{{title|}}}
| label14    = Salary
| data14     = {{{salary|}}}
| label15    = Net&nbsp;worth
| data15     = {{{networth|}}}
| label16    = Height
| data16     = {{{height|}}}
| label17    = Weight
| data17     = {{{weight|}}}
| label18    = Known&nbsp;for
| data18     = {{{known|{{{known_for|}}}}}}
| label19    = Term
| data19     = {{{term|}}}
| label20    = Predecessor
| data20     = {{{predecessor|}}}
| label21    = Successor
| data21     = {{{successor|}}}
| label22    = Political&nbsp;party
| data22     = {{{party|}}}
| label23    = Board member&nbsp;of
| data23     = {{{boards|}}}
| label24    = Religious beliefs
| data24     = {{{religion|}}}
| label25    = Spouse
| data25     = {{{spouse|}}}
| label26    = Partner
| data26     = {{{partner|}}}
| label27    = Children
| data27     = {{{children|}}}
| label28    = Parents
| data28     = {{{parents|}}}
| label29    = Relatives
| data29     = {{{relations|{{{relatives|}}}}}}

| data30     = {{#if:{{{signature|}}}|'''Signature'''<div style="padding-top:0.3em;">[[Image:{{{signature}}}|128px]]</div>}}
| data31     = {{#if:{{{website|}}}| '''Website'''<br />{{{website}}} }}
| data32     = {{#if:{{{footnotes|}}}|<div style="text-align:left;"><div style="border-top:1px solid;">'''Notes'''</div><div style="line-height:1.2em;">{{{footnotes}}}</div></div>}}
}}<noinclude>{{pp-semi-template|small=yes}}{{#ifeq:{{SUBPAGENAME}}|sandbox |{{Template sandbox notice}} }}{{documentation}}<!---Please add metadata to the <includeonly> section at the bottom of the /doc subpage---></noinclude>
END

$invocation = <<'END';
 infobox
| bodyclass  = biography vcard
| bodystyle  = width:{{#if:{{{box_width|}}}|{{{box_width}}} |22em}}; font-size:95%; text-align:left;
| above      = '''{{{name|{{PAGENAME}}}}}'''
| aboveclass = fn
| abovestyle = text-align:center; font-size:125%;
| image      = {{#if:{{{image|}}}|[[Image:{{{image}}}|{{#if:{{{image_size|{{{imagesize|}}}}}}|{{{image_size|{{{imagesize}}}}}}|225px}}]]}}
| imageclass = {{image class names|{{{image}}}}}
| imagestyle = padding:4pt; line-height:1.25em; text-align:center; font-size:8pt;
| caption    = <div style="padding-top:2pt;">{{{caption|}}}</div>
| labelstyle = padding:0.2em 1.0em 0.2em 0.2em; background:transparent; line-height:1.2em; text-align:left; font-size:90%;
| datastyle  = padding:0.2em; line-height:1.3em; vertical-align:middle; font-size:90%;

| label1     = {{#if:{{{birth_name|}}}{{{birth_date|}}}{{{birth_place|}}}|Born}}
| data1      = {{#if:{{{birth_name|}}}|{{{birth_name}}}<br />}}{{#if:{{{birth_date|}}} |{{{birth_date}}}<br />}}{{{birth_place|}}}
| label2     = {{#if:{{{death_date|}}}{{{death_place|}}}|Died }}
| data2      = {{#if:{{{death_date|}}}|{{{death_date}}}<br />}}{{{death_place|}}}
| label3     = Cause&nbsp;of death
| data3      = {{{death_cause|}}}
| label4     = Burial&nbsp;place
| class4     = label
| data4      = {{{resting_place|}}}{{#if:{{{resting_place_coordinates|}}}|<br />{{{resting_place_coordinates}}} }}
| label5     = Residence
| class5     = label
| data5      = {{{residence|}}}
| label6     = Nationality
| data6      = {{{nationality|}}}
| label7     = Other&nbsp;names
| class7     = nickname
| data7      = {{{other_names|}}}
| label8     = Education
| data8      = {{{education|}}}
| label9     = Alma&nbsp;mater
| data9      = {{{alma_mater|}}}
| label10    = Occupation
| data10     = {{{occupation|}}}
| label11    = Employers
| data11     = {{{employer|}}}
| label12    = Home&nbsp;town
| data12     = {{{home_town|}}}
| label13    = Title
| data13     = {{{title|}}}
| label14    = Salary
| data14     = {{{salary|}}}
| label15    = Net&nbsp;worth
| data15     = {{{networth|}}}
| label16    = Height
| data16     = {{{height|}}}
| label17    = Weight
| data17     = {{{weight|}}}
| label18    = Known&nbsp;for
| data18     = {{{known|{{{known_for|}}}}}}
| label19    = Term
| data19     = {{{term|}}}
| label20    = Predecessor
| data20     = {{{predecessor|}}}
| label21    = Successor
| data21     = {{{successor|}}}
| label22    = Political&nbsp;party
| data22     = {{{party|}}}
| label23    = Board member&nbsp;of
| data23     = {{{boards|}}}
| label24    = Religious beliefs
| data24     = {{{religion|}}}
| label25    = Spouse
| data25     = {{{spouse|}}}
| label26    = Partner
| data26     = {{{partner|}}}
| label27    = Children
| data27     = {{{children|}}}
| label28    = Parents
| data28     = {{{parents|}}}
| label29    = Relatives
| data29     = {{{relations|{{{relatives|}}}}}}

| data30     = {{#if:{{{signature|}}}|'''Signature'''<div style="padding-top:0.3em;">[[Image:{{{signature}}}|128px]]</div>}}
| data31     = {{#if:{{{website|}}}| '''Website'''<br />{{{website}}} }}
| data32     = {{#if:{{{footnotes|}}}|<div style="text-align:left;"><div style="border-top:1px solid;">'''Notes'''</div><div style="line-height:1.2em;">{{{footnotes}}}</div></div>}}
END

cmpthese(-1, {
  'c-split' 		=> sub { &ctemplates::splitOnTemplates($text);},
  'perl-split'		=> sub { &templates::splitOnTemplates($text);}
});

cmpthese(-1, {
  'c-invoc' 		=> sub { &ctemplates::splitTemplateInvocation($invocation);},
  'perl-invoc'		=> sub { &templates::splitTemplateInvocation($invocation);}
});
