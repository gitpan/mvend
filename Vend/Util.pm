# $Id: Util.pm,v 1.4 1996/05/25 07:06:03 mike Exp mike $

package Vend::Util;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(

blank
combine
commify
currency
file_modification_time
fill_table
get_files
is_no
is_yes
logData
logError
lockfile
unlockfile
readfile
readin
random_string
setup_escape_chars
escape_chars
unescape_chars
send_mail
secure_vendUrl
tabbed
tag_nitems
tag_item_quantity
tainted
uneval
vendUrl
wrap

);
@EXPORT_OK = qw(append_field_data append_to_file csv field_line tabbed);

use strict;
use Carp;
use Config;
use Fcntl;
# We now use File::Lock for Solaris and SGI systems
use File::Lock;

### END CONFIGURABLE MODULES


## ESCAPE_CHARS

$ESCAPE_CHARS::ok_in_filename = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .
    'abcdefghijklmnopqrstuvwxyz' .
    '0123456789' .
    '-_.$/';

sub setup_escape_chars {
    my($ok, $i, $a, $t);

    foreach $i (0..255) {
        $a = chr($i);
        if (index($ESCAPE_CHARS::ok_in_filename,$a) == -1) {
	    $t = '%' . sprintf( "%02X", $i );
        } else {
	    $t = $a;
        }
        $ESCAPE_CHARS::translate[$i] = $t;
    }
}

# Replace any characters that might not be safe in a filename (especially
# shell metacharacters) with the %HH notation.

sub escape_chars {
    my($in) = @_;
    my($c, $r);

    $r = '';
    foreach $c (split(//, $in)) {
	$r .= $ESCAPE_CHARS::translate[ord($c)];
    }

    # safe now
    $r =~ m/(.*)/;
    $r = $1;
    #print Vend::DEBUG "escape_chars tainted: ", tainted($r), "\n";
    $1;
}

# Replace the escape notation %HH with the actual characters.

sub unescape_chars {
    my($in) = @_;

    $in =~ s/%(..)/chr(hex($1))/ge;
    $in;
}

# Returns its arguments as a string of tab-separated fields.  Tabs in the
# argument values are converted to spaces.

sub tabbed {        
    return join("\t", map { $_ = '' unless defined $_;
                            s/\t/ /g;
                            $_;
                          } @_);
}


sub commify {
	local($_) = shift;
   	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}

# Return AMOUNT formatted as currency.

sub currency {
    my($amount) = @_;

    if(is_yes($Config::PriceCommas)) {
        commify sprintf("%.2f", $amount);
    }
    else {
        sprintf("%.2f", $amount);
    }
}


## random_string

# leaving out 0, O and 1, l
my $random_chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

# Return a string of random characters.

sub random_string {
    my ($len) = @_;
    $len = 8 unless $len;
    my ($r, $i);

    $r = '';
    for ($i = 0;  $i < $len;  ++$i) {
	$r .= substr($random_chars, int(rand(length($random_chars))), 1);
    }
    $r;
}


sub combine {
    my $r;

    if (@_ == 1) {
	$_[0];
    } elsif (@_ == 2) {
	"$_[0] and $_[1]";
    } else {
	$r = $_[0];
	foreach (1 .. $#_ - 1) {
	    $r .= ", $_[$_]";
	}
	$r .= ", and " . $_[$#_];
	$r;
    }
}

sub blank {
    my ($x) = @_;
    return (!defined($x) or $x eq '');
}


## UNEVAL

# Returns a string representation of an anonymous array, hash, or scaler
# that can be eval'ed to produce the same value.
# uneval([1, 2, 3, [4, 5]]) -> '[1,2,3,[4,5,],]'

sub uneval {
    my($o) = @_;		# recursive
    my($r, $s, $i, $key, $value);

    $r = ref $o;
    if (!$r) {
	$o =~ s/[\\"\$@]/\\$&/g;
	$s = '"' . $o . '"';
    } elsif ($r eq 'ARRAY') {
	$s = "[";
	foreach $i (0 .. $#$o) {
	    $s .= uneval($o->[$i]) . ",";
	}
	$s .= "]";
    } elsif ($r eq 'HASH') {
	$s = "{";
	while (($key, $value) = each %$o) {
	    $s .= "'$key' => " . uneval($value) . ",";
	}
	$s .= "}";
    } else {
	$s = "'something else'";
    }

    $s;
}

## ERROR

# Log the error MSG to the error file.

sub logError {
    my($msg) = @_;
    my $prefix = '';

    eval {
    open(Vend::ERROR, ">>$Config::ErrorFile") or die "open\n";
    lockfile(\*Vend::ERROR, 1, 1) or die "lock\n";
    $prefix = "$$: " if $Config::MultiServer;
    seek(Vend::ERROR, 0, 2) or die "seek\n";
    print(Vend::ERROR $prefix, `date`) or die "write to\n";
    print(Vend::ERROR $prefix, "$msg\n") or die "write to\n";
    unlockfile(\*Vend::ERROR) or die "unlock\n";
    close(Vend::ERROR) or die "close\n";
    };
    if ($@) {
    chomp $@;
    print "\nCould not $@ error file '";
    print $Config::ErrorFile, "':\n$!\n";
    print "to report this error:\n", $msg;
    exit 1;
    }
}

# Log data fields to a data file.

sub logData {
    my($file,@msg) = @_;
    my $prefix = '';

	$file = ">>$file" unless $file =~ /^[|>]/;

	my $msg = tabbed @msg;

    eval {
		open(Vend::LOGDATA, "$file") or die "open\n";
		unless($file =~ /^[|]/) {
			lockfile(\*Vend::LOGDATA, 1, 1) or die "lock\n";
			seek(Vend::LOGDATA, 0, 2) or die "seek\n";
		}
		print(Vend::LOGDATA "$msg\n") or die "write to\n";
		unless($file =~ /^[|]/) {
			unlockfile(\*Vend::LOGDATA) or die "unlock\n";
		}
		close(Vend::LOGDATA) or die "close\n";
    };
    if ($@) {
    chomp $@;
    logError "Could not $@ log file '" . $file . "':\n$!\n" .
    		"to log this data:\n" .  $msg ;
    exit 1;
    }
}


=head2 C<wrap($str, $width)>

Wraps the passed string to fit the specified maximum width.  An array
of lines, each $width or less, is returned.  The line is wrapped at a
space if one exists in the string.

(The function could also wrap on other characters, such as a dash, but
currently does not).

=cut

sub wrap {
    my ($str, $width) = @_;
    my @a = ();
    my ($l, $b);

    for (;;) {
        $str =~ s/^ +//;
        $l = length($str);
        last if $l == 0;
        if ($l <= $width) {
            push @a, $str;
            last;
        }
        $b = rindex($str, " ", $width - 1);
        if ($b == -1) {
            push @a, substr($str, 0, $width);
            $str = substr($str, $width);
        }
        else {
            push @a, substr($str, 0, $b);
            $str = substr($str, $b + 1);
        }
    }
    return @a;
}


sub fill_table {
    my ($widths, $aligns, $strs, $prefix, $separator, $postfix, $push_down) = @_;
    my ($x, @text, $y, $align, $cell, $l, $width);

    my $last_x = $#$widths;
    my $last_y = -1;
    my $texts = [];

    for $x (0 .. $#$widths) {
        die "Width value not specified: $widths->[$x]\n"
            unless $widths->[$x] > 0;
        @text = wrap($strs->[$x], $widths->[$x]);
        $last_y = $#text if $#text > $last_y;
        $texts->[$x] = [@text];
    }


    my ($column, $this_height, $fill, $i);
    if ($push_down) {
        for $x (0 .. $last_x) {
            $column = $texts->[$x];
            $this_height = $#$column;
            $fill = ' ' x $widths->[$x];
            for $i (1 .. $last_y - $this_height) {
                unshift @$column, $fill;
            }
        }
    }

    for $y (0 .. $last_y) {
        for $x (0 .. $last_x) {
            $width = $widths->[$x];
            if ($y > $#{$texts->[$x]}) {
                $cell = ' ' x $width;
            }
            else {
                $align = $aligns->[$x];
                $cell = $texts->[$x][$y];
                $cell =~ s/^ +//;
                $cell =~ s/ +$//;
                $l = length($cell);
                if ($l < $width) {
                    if ($align eq '<') {
                        $cell .= ' ' x ($width - $l);
                    }
                    elsif ($align eq '|') {
                        $l = length($cell);
                        $cell = ' ' x (($width - $l) / 2) . $cell;
                        $cell .= ' ' x ($width - length($cell));
                    }
                    elsif ($align eq '>') {
                        $cell = ' ' x ($width - $l) . $cell;
                    }
                    else { die "Unknown alignment specified: $align" }
                }
            }
            $texts->[$x][$y] = $cell;
        }
    }

    my $r = '';
    for $y (0 .. $last_y) {
        $r .= $prefix;
        for $x (0 .. $last_x - 1) {
            $r .= $texts->[$x][$y] . $separator;
        }
        $r .= $texts->[$last_x][$y] . $postfix;
    }
    return $r;
}

sub file_modification_time {
    my ($fn) = @_;
    my @s = stat($fn) or die "Can't stat '$fn': $!\n";
    return $s[9];
}



# Returns its arguments as a string of comma separated and quoted
# fields.  Double quotes in the argument values are converted to
# two double quotes.

sub csv {
    return join(',', map { $_ = '' unless defined $_;
                           s/\"/\"\"/g;
                           '"'. $_ .'"';
                         } @_);
}


# Appends the string $value to the end of $filename.  The file is opened
# in append mode, and the string is written in a single system write
# operation, so this function is safe in a multiuser environment even
# without locking.

sub append_to_file {
    my ($filename, $value) = @_;

    open(OUT, ">>$filename") or die "Can't append to '$filename': $!\n";
    syswrite(OUT, $value, length($value))
        == length($value) or die "Can't write to '$filename': $!\n";
    close(OUT);
}

# Converts the passed field values into a single line in Ascii delimited
# format.  Two formats are available, selected by $format:
# "comma_separated_values" and "tab_separated".

sub field_line {
    my $format = shift;

    return csv(@_) . "\n"    if $format eq 'comma_separated_values';
    return tabbed(@_) . "\n" if $format eq 'tab_separated';

    die "Unknown format: $format\n";
}

# Appends the passed field values onto the end of $filename in a single
# system operation.

sub append_field_data {
    my $filename = shift;
    my $format = shift;

    append_to_file($filename, field_line($format, @_));
}


## READIN

# Reads in a page from the page directory with the name FILE and ".html"
# appended.  Returns the entire contents of the page, or undef if the
# file could not be read.

sub readin {
    my($file) = @_;
    my($fn, $contents);
    local($/);

    $fn = "$Config::PageDir/" . escape_chars($file) . ".html";
    if (open(Vend::IN, $fn)) {
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }
    $contents;
}

# Reads in an arbitrary file.  Returns the entire contents,
# or undef if the file could not be read.
# Careful, needs the full path, or will be read relative to
# VendRoot..and will return binary. Should be tested by
# the user.
sub readfile {
    my($file) = @_;
    my($fn, $contents);
    local($/);

    if (open(Vend::IN, $file)) {
		undef $/;
		$contents = <Vend::IN>;
		close(Vend::IN);
    } else {
		$contents = undef;
    }
    $contents;
}

# Calls readin to get files, then returns an array of values
# with the file contents in each entry. Returns a single newline
# if not found or empty. For getting buttonbars, helps,
# and randoms.
sub get_files {
	my(@files) = @_;
	my(@out);
	my($file, $contents);

	foreach $file (@files) {
		push(@out,"\n") unless
			push(@out,readin($file));
	}
	
	@out;
}

sub is_yes {
    return( defined($_[$[]) && ($_[$[] =~ /^[yYtT1]/));
}

sub is_no {
	return( !defined($_[$[]) || ($_[$[] =~ /^[nNfF0]/));
}

# Returns a URL which will run the ordering system again.  Each URL
# contains the session ID as well as a unique integer to avoid caching
# of pages by the browser.

sub vendUrl
{
    my($path, $arguments) = @_;
    my $r = $Config::VendURL;

	if(defined $Config::AlwaysSecure{$path}) {
		$r = $Config::SecureURL;
	}

    $r .= '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

sub secure_vendUrl
{
    my($path, $arguments) = @_;
    my($r);

	return undef unless $Config::SecureURL;

    $r = $Config::SecureURL . '/' . $path . '?' . $Vend::SessionID .
	';' . $arguments . ';' . ++$Vend::Session->{'pageCount'};
    $r;
}    

## SEND_MAIL

# Send a mail message to the email address TO, with subject SUBJECT, and
# message BODY.  Returns true on success.

sub send_mail {
    my($to, $subject, $body) = @_;
    my($ok);

    $ok = 0;
    SEND: {
		open(Vend::MAIL,"|$Config::SendMailProgram $to") or last SEND;
		print Vend::MAIL "To: $to\n", "Subject: $subject\n\n", $body
	    	or last SEND;
		close Vend::MAIL or last SEND;
		$ok = ($? == 0);
    }
    
    if (!$ok) {
		logError("Unable to send mail using $Config::SendMailProgram\n" .
		 	"To '$to'\n" .
		 	"With subject '$subject'\n" .
		 	"And body:\n$body");
    }

    $ok;
}

sub tainted {
    my($v) = @_;
    my($r);
    local($@);

    eval { open(Vend::FOO, ">" . "FOO" . substr($v,0,0)); };
    close Vend::FOO;
    ($@ ? 1 : 0);
}

my $debug = 0;
my $use = undef;

### flock locking

# sys/file.h:
my $flock_LOCK_SH = 1;          # Shared lock
my $flock_LOCK_EX = 2;          # Exclusive lock
my $flock_LOCK_NB = 4;          # Don't block when locking
my $flock_LOCK_UN = 8;          # Unlock

sub flock_lock {
    my ($fh, $excl, $wait) = @_;
    my $flag = $excl ? $flock_LOCK_EX : $flock_LOCK_SH;

    if ($wait) {
        flock($fh, $flag) or confess "Could not lock file: $!\n";
        return 1;
    }
    else {
        if (! flock($fh, $flag | $flock_LOCK_NB)) {
            if ($! =~ m/^Try again/
                or $! =~ m/^Resource temporarily unavailable/
                or $! =~ m/^Operation would block/) {
                return 0;
            }
            else {
                confess "Could not lock file: $!\n";
            }
        }
        return 1;
    }
}

sub flock_unlock {
    my ($fh) = @_;
    flock($fh, $flock_LOCK_UN) or confess "Could not unlock file: $!\n";
}


### fcntl locking now done by File::Lock

sub fcntl_lock {
    my ($fh, $excl, $wait) = @_;
	my $cmd = '';
    $cmd .= $excl ? 'w' : 'r';
    $cmd .= $wait ? 'b' : 'n';


    File::Lock::fcntl($fh,$cmd)
    	or confess "Could not lock file: $!\n";
	1;
}

sub fcntl_unlock {
    my ($fh) = @_;
    File::Lock::fcntl($fh,'u')
    	or confess "Could not unlock file: $!\n";
    1;
}

### Select based on os

my $lock_function;
my $unlock_function;

unless (defined $use) {
    my $os = $Vend::Util::Config{'osname'};
    warn "lock.pm: os is $os\n" if $debug;
    if ($os eq 'solaris' or $os eq 'irix') {
        $use = 'fcntl';
    }
    else {
        $use = 'flock';
    }
}
        
if ($use eq 'fcntl') {
    warn "lock.pm: using fcntl locking\n" if $debug;
    $lock_function = \&fcntl_lock;
    $unlock_function = \&fcntl_unlock;
}
else {
    warn "lock.pm: using flock locking\n" if $debug;
    $lock_function = \&flock_lock;
    $unlock_function = \&flock_unlock;
}
    
sub lockfile {
    &$lock_function(@_);
}

sub unlockfile {
    &$unlock_function(@_);
}

# Returns the number ordered of a single item code

sub tag_item_quantity {
	my($code) = @_;
    my($i);
    foreach $i (0 .. $#$Vend::Items) {
		return $Vend::Items->[$i]->{'quantity'}
			if $code eq $Vend::Items->[$i]->{'code'};
    }
	0;
}

# Returns the total number of items ordered.

sub tag_nitems {
    my($total, $i);

    $total = 0;
    foreach $i (0 .. $#$Vend::Items) {
	$total += $Vend::Items->[$i]->{'quantity'};
    }
    $total;
}


1;