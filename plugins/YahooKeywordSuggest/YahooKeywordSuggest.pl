package MT::Plugin::OMV::YahooKeywordSuggest;
########################################################################
#   YahooKeywordSuggest - Suggest the suitable keywords with Yahoo! web service
#   @see http://developer.yahoo.co.jp/jlp/MAService/V1/parse.html
#           Copyright (c) 2008 Piroli YUKARINOMIYA (MagicVox)
#           @see http://www.magicvox.net/archive/2008/04151715/

use strict;
use MT;
use MT::Entry;
use MT::Page;
use MT::Util qw( remove_html );
use LWP::UserAgent;
use XML::Simple;

### Trigger phrase to invoke my function
use constant TRIGGER_PHRASE =>          '???';

### End point of Yahoo! web service
use constant YAHOO_API_ENDPOINT =>      'http://api.jlp.yahoo.co.jp/MAService/V1/parse';



### Register as a plugin
use vars qw( $MYNAME $VERSION );
$MYNAME = 'YahooKeywordSuggest';
$VERSION = '0.10';

use base qw( MT::Plugin );
my $plugin = __PACKAGE__->new({
    name => $MYNAME,
    version => $VERSION,
    id => $MYNAME,
    key => $MYNAME,
    author_name => 'Piroli YUKARINOMIYA',
    author_link => 'http://www.magicvox.net/',
    doc_link => 'http://www.magicvox.net/archive/2008/04151715/',
    description => <<PERLHEREDOC,
Suggest the suitable keywords of the entry with the morphological analysis of Yahoo! web service
PERLHEREDOC
    # Configurations
    system_config_template => \&_tmpl_system_config,
    settings => new MT::PluginSettings([
        ['yahoo_appid', { Default => undef, Scope => 'system' }],
        ['num_suggest', { Default => 10, Scope => 'system' }],
        ['get_title',   { Default => 1, Scope => 'system' }],
        ['get_text',    { Default => 1, Scope => 'system' }],
        ['get_more',    { Default => 1, Scope => 'system' }],
        ['get_excerpt', { Default => 0, Scope => 'system' }],
    ]),
});
MT->add_plugin( $plugin );

sub instance { $plugin }



### Plugin configurations
sub _tmpl_system_config {
    return <<PERLHEREDOC;
<mtapp:setting id="yahoo_appid" label="Yahoo! Application ID">
  <input type="text" size="20" name="yahoo_appid" id="yahoo_appid" value="<TMPL_VAR NAME=YAHOO_APPID ESCAPE=HTML>" />
</mtapp:setting>

<mtapp:setting id="num_suggest" label="Number of Keywords">
  <input type="text" size="5" name="num_suggest" id="num_suggest" value="<TMPL_VAR NAME=NUM_SUGGEST ESCAPE=HTML>" />
</mtapp:setting>

<mtapp:setting id="suggest_with" label="Suggest with">
  <ul>
    <li><input type="checkbox" name="get_title" value="1" <TMPL_IF NAME=GET_TITLE>checked</TMPL_IF>/><MT_TRANS phrase="Entry Title"></li>
    <li><input type="checkbox" name="get_text" value="1" <TMPL_IF NAME=GET_TEXT>checked</TMPL_IF>/><MT_TRANS phrase="Entry Body"></li>
    <li><input type="checkbox" name="get_more" value="1" <TMPL_IF NAME=GET_MORE>checked</TMPL_IF>/><MT_TRANS phrase="Entry Extended Text"></li>
    <li><input type="checkbox" name="get_excerpt" value="1" <TMPL_IF NAME=GET_EXCERPT>checked</TMPL_IF>/><MT_TRANS phrase="Entry Excerpt"></li>
  </ul>
</mtapp:setting>
PERLHEREDOC
}



### Regist callback
MT::Entry->add_callback( 'pre_save', 9, $plugin, \&_cb_object_pre_save );
MT::Page->add_callback( 'pre_save', 9, $plugin, \&_cb_object_pre_save );
sub _cb_object_pre_save {
    my( $cb, $obj ) = @_;
    $obj->keywords eq TRIGGER_PHRASE
        or return;# do nothing

    ### Yahoo! application ID
    my $yahoo_appid = &instance->get_config_value( 'yahoo_appid' )
        or return $cb->error( "You need to get and configure your Yahoo! application ID for $MYNAME" );

    ###
    my $text;
    $text .= $obj->title. "\n"      if &instance->get_config_value( 'get_title' );
    $text .= $obj->text. "\n"       if &instance->get_config_value( 'get_text' );
    $text .= $obj->text_more. "\n"  if &instance->get_config_value( 'get_more' );
    $text .= $obj->excerpt. "\n"    if &instance->get_config_value( 'get_excerpt' );

    ### Retrieve with Yahoo!'s web service
    my $ua = new LWP::UserAgent
        or return $cb->error( 'Failed to initialize a component - LWP::UserAgent' );
    $ua->agent( __PACKAGE__. '/'. $VERSION );
    my %params = (
        appid => $yahoo_appid,
        sentence => remove_html( $text ),
        results => 'uniq',
        response => 'surface',
        filter => '9',
    );
    my $res = $ua->post( YAHOO_API_ENDPOINT, \%params )
        or return;
    $res->is_success
        or return;   # but HTTP errors
    my $yahoo_result = $res->content
        or return;   # empty content

    ### Parse the results
    my $xs = new XML::Simple
        or return $cb->error( 'Failed to initialize a component - XML::Simple' );
    my $ref = $xs->XMLin( $yahoo_result )
        or return; # failed to parse
    $ref = $ref->{uniq_result}  or return;
    $ref = $ref->{word_list}    or return;
    $ref = $ref->{word}         or return;

    ### Get keywords
    my @keywords = ();
    my $count = &instance->get_config_value( 'num_suggest' ) || 10;
    while( 0 < $count-- && defined( my $word = shift @{$ref})) {
        push @keywords, $word->{surface} || '';
    }

    ### Set keywords list
    $obj->keywords( join ' ', @keywords );
}

1;