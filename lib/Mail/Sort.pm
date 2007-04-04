# $Id: Sort.pm 36 2007-04-04 02:45:22Z itz $

package Mail::Sort;

use Mail::Sort::Base;
@ISA = qw(Mail::Sort::Base);

use strict;
use v5.6.0;

our $VERSION='20070404';

# various junk matching recipes
sub fake_received {
    my $self = $_[0];
    $self->header_match('received', '\[[[0-9.]*([03-9][0-9][0-9]|2[6-9][0-9]|25[6-9])')
        or $self->header_match('Received', 'from Unknown/Local')
        or $self->header_match('received', 'unknown host')
        or $self->header_match('Received', 'from HOST')
        or $self->header_match('Received', 'HELO HOST');
}

sub missing_required {
    my $self = $_[0];
    !$self->header_match('from') or !$self->header_match('date');
}

sub invalid_date {
    my $self = $_[0];
    !$self->header_match('date','(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), )?[0-3 ]?[0-9] (?:Jan|Feb|Ma[ry]|Apr|Ju[nl]|Aug|Sep|Oct|Nov|Dec) (?:[12][901])?[0-9]{2} [0-2][0-9](?:\:[0-5][0-9]){1,2} (?:[+-][0-9]{4}|UT|[A-Z]{2,3}T)(?:\s+\(.*\))?');
}

sub overflow_attempt {
    my $self = $_[0];
    $self->header_match('received',
'.....................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................\
..........................................................................');
}

sub bad_x_uidl {
    my $self = $_[0];
    $self->header_match('x-uidl')
        and !$self->header_start('x-uidl',"[ 	]*[0-9a-f]+[ 	]*\$");
}

sub oceanic_date {
    my $self = $_[0];
    $self->header_match('(date|received)','-0600 \(EST\)')
        or $self->header_match('date','[-+](?:1[4-9]\d\d|[2-9]\d\d\d)');
}

sub empty_header {
    my $self = $_[0];
    $self->header_start('(from|to|reply-to)', "[ 	]*[<>]*[ 	]*\$");
}

sub visible_bcc {
    my $self = $_[0];
    $self->header_match('bcc');
}

sub eight_bit_header {
    my $self = $_[0];
    $self->header_match('(from|subject)','[\x80-\xff][\x80-\xff][\x80-\xff][\x80-\xff]');
}

sub faraway_charset {
    my $self = shift;
    my $charsets_rx = '(' . join('|', @_) . ')';
    $self->header_start('(from|subject)',join('','=\?', $charsets_rx, '\?'))
        or $self->header_match('content-type',join('','charset="', $charsets_rx, '"'));
}

sub asian_origin {
    my $self = $_[0];
    $self->eight_bit_header() or $self->faraway_charset('iso-?2022-?jp', 'gb-?2312');
}

sub no_message_id {
    my $self = $_[0];
    not $self->header_start('message-id',"\\s*<\\s*[^> ][^>]*\\s*>\\s*(\\(added by [^<>()]+\\)\\s*)?\$");
}

sub strange_mime {
    my $self = $_[0];
    $self->header_match('MiME-Version');
}

sub subject_free_caps {
    my $self = $_[0];
    $self->header_match('Subject', '\bFREE\b');
}

sub subject_all_caps {
   my $self = $_[0];
   not $self->header_match('Subject','[a-z]');
}

sub subject_has_spaces {
    my $self = $_[0];
    $self->header_match('subject','( {6}|[\t])\S');
}

sub too_many_recipients {
    my ($self, $limit) = @_;
    $self->destination_match("(,.*){$limit}");
}

sub html_only {
    my $self = $_[0];
    $self->header_match('content-type','text/html');
}

sub address_as_realname {
    my $self = $_[0];
    $self->header_start('"([^"@]+\@[^"@]+)"\s+<\1>');
}

sub base64_text {
    my $self = $_[0];
    $self->header_match('content-type','text/plain')
        and $self->header_match('content-transfer-encoding','base64');
}

sub missing_mimeole {
    my $self = $_[0];
    $self->header_match('x-msmail-priority')
        # squirrelmail seems to insert this header, so make an exception for it
        and not $self->header_match('x-mailer','squirrelmail')
        and not $self->header_match('x-mimeole');
}

sub msgid_spam_chars {
    my $self = $_[0];
    $self->header_match('message-id','[:}{,!\/]');
}

sub from_ends_in_digit {
    my $self = $_[0];
    $self->header_match('from','\d\@');
}

sub received_by_smtpd32 {
    my $self = $_[0];
    $self->header_match('received','smtpd32');
}

# razor integration

sub razor_check {
    require Razor::String;
    require Razor::Config;
    require Razor::Client;

    my $self = $_[0];
    my @lines = ("\n", @{$self->{body}});
    my $hash = Razor::String::hash (\@lines);
    my $config = Razor::Config::findconf('razor.conf');
    my $client = Razor::Client->new ($config);
    my $reply = $client->check(sigs => [$hash]);
    defined $reply && return $reply->[0];
    $self->log(1, "razor check failed: $Razor::Client::errstr");
    0;
}

# spamassassin integration

sub _as_string {
    my $self = $_[0];
    return join ('', @{$self->{head}}, "\n", @{$self->{body}});
}

sub spamassassin_check {
    require Mail::SpamAssassin;

    my $self = shift;
    my $checker = { @_ };
    Mail::SpamAssassin->new($checker);
    my $status = $checker->check_message_text($self->_as_string);
    my $total = $status->get_hits();
    my @hits = split /\s*,\s*/, $status->get_names_of_tests_hit();
    my $report = $status->get_report();
    my %hitlist = ('total' => $total);
    foreach (@hits) {
        $report =~ m( \n\s*SPAM:\s*$_\s*\((-?[0-9]+\.[0-9]+) )x ;
        $hitlist{$_} = $1;
    }
    $status->finish();
    return \%hitlist;
}

1;
