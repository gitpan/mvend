# Vend/TextSearch.pm:  Search indexes with Perl
#
# $Id: TextSearch.pm,v 1.3 1996/08/24 17:55:42 mike Exp mike $
#
# ADAPTED FOR USE WITH MINIVEND from Search::TextSearch
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


#
##  vi regex to delete debugs     %s/^\(.*$s->debug\)/#\1/
##  vi regex to restore debugs     %s/^\([^#]*\)#\(.*$s->debug\)/\1\2/
#

package Vend::TextSearch;
require Vend::Search;
@ISA = qw(Vend::Search);

$VERSION = substr(q$Revision: 1.3 $, 10);

use Text::ParseWords;
use Search::Dict;
use strict;

sub new {
    my ($class, %options) = @_;
	my $self = new Vend::Search;
	my ($key,$val);
	init($self);
	while ( ($key,$val) = each %options) {
		$self->{global}->{$key} = $val;
	}
	bless $self, $class;
}

sub init {
	my $s = shift;
	my $g = $s->{global};
	$g->{'dict_look'}	= '';
	$g->{'dict_end'}	= '';
	$g->{'dict_order'}	= 0;
	$g->{'dict_case'} 	= 0;
}

sub version {
	$Vend::TextSearch::VERSION;
}

sub search {

	my($s,%options) = @_;
    my $g = $s->{global};

#	$s->debug("Vend::TextSearch");

	my($delim,$string);
	my($max_matches,$mod,$return_delim,$spec);
	my($code,$count,$matches_to_send,@out);
	my($index_delim,$limit_sub,$return_sub);
	my($dict_limit,$f,$key,$val,$range_op);
	my($searchfile,@searchfiles);
	my(@specs);
	my(@pats);

	while (($key,$val) = each %options) {
		$g->{$key} = $val;
	}

 	$index_delim = $g->{index_delim};
	$return_delim = defined $g->{return_delim}
				   ? $g->{return_delim}
				   : $index_delim;

	$g->{matches} = 0;

	if($g->{search_spec}) {
	  	@specs = $g->{search_spec};
	}
	else {
		@specs = @{$s->{specs}};
	}

    if(ref $g->{range_look}) {
        no strict 'refs';
        unless( scalar(@{$g->{range_look}}) == scalar(@{$g->{range_min}}) and
                scalar(@{$g->{range_look}}) == scalar(@{$g->{range_max}}) ) {
			&{$g->{error_routine}} ($g->{error_page},
					"Must have min and max values for range.");
			$g->{matches} = -1;
			return undef;
		}
		$range_op = 1;
	}

	@specs = '' if @specs == 0;

  SPEC_CHECK: {
	last SPEC_CHECK if $g->{return_all};
	foreach $string (@specs) {
		if(length($string) < $g->{min_string}) {
			my $msg = <<EOF;
Search strings must be at least $g->{min_string} characters.
You had '$string' as one of your search strings.
EOF
			&{$g->{error_routine}}($g->{error_page}, $msg);
			$g->{matches} = -1;
			return undef;
		}
	}

	if($g->{exact_match}) {
		for(@specs) {
			s/"//g;
			$_ = '"' . $_ . '"';
		}
	}

	$spec = join ' ', @specs;

	if ($g->{all_chars} ||= 0) {
        $spec =~ s/"/__QUOTE__/g;
        $spec =~ s/ /__SPACE__/g;
        $spec =~ s/,/__COMMA__/g;
        $spec = quotemeta $spec;
        $spec =~ s/__QUOTE__/"/g;
        $spec =~ s/__SPACE__/ /g;
        $spec =~ s/__COMMA__/,/g;
	}
	else {
		$spec =~ s/[^"$\d\w\s*]//g;
		unless ($g->{or_search}) {
			$spec =~ s'\*'\S*'g
		}
		else {
			$spec =~ s:(\S+)\*:$1\S*:g
		}
	}

#	$s->debug("spec='$spec'");

	$spec =~ /(.*)/;
	$spec = $1;
	@pats = shellwords($spec);
#	$s->debug("pats: '", join("', '", @pats), "'");
  } # last SPEC_CHECK

	if ($g->{return_all}) {
		$f = sub {1};
	}
	elsif ($g->{or_search}) {
		eval {$f = $s->create_search_or(	$g->{case_sensitive},
										$g->{substring_match},
										@pats					)};
	}
	else  {	
		eval {$f = $s->create_search_and(	$g->{case_sensitive},
										$g->{substring_match},
										@pats					)};
	}
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	eval {$limit_sub = $s->get_limit($f)};
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	eval {$return_sub = $s->get_return()};
	if($@) {
		&{$g->{error_routine}}($g->{error_page}, $@);
		$g->{matches} = -1;
		return undef;
	}

	$max_matches = int($g->{max_matches});

	$g->{overflow} = 0;

#	$s->debug('fields/specs: ', scalar @{$s->{fields}}, " ", scalar @{$s->{specs}});

	if($g->{dict_end}) {
		if(!$g->{dict_order} && !$g->{dict_fold}) {
			$dict_limit = sub {
					$_[0] gt $g->{dict_end};
			};
		}
		elsif(!$g->{dict_order}) {
			$dict_limit = sub {
					"\L$_[0]" gt "\L$g->{dict_end}";
			};
		}
		elsif(!$g->{dict_fold}) {
			$dict_limit = sub {
					my($line) = @_;
					my($end) = $g->{dict_end};
					$line =~ tr/A-Za-z0-9_ //cd;
					$end =~ tr/A-Za-z0-9_ //cd;
					$line gt $end;
			};
		}
		else {
			$dict_limit = sub {
					my($line) = lc @_;
					my($end) = lc $g->{dict_end};
					$line =~ tr/a-z0-9_ //cd;
					$end =~ tr/a-z0-9_ //cd;
					$line gt $end;
			};
		}
	}
		

	if(ref($g->{search_file}) =~ /^ARRAY/) {
		@searchfiles = @{$g->{search_file}};
	}
	elsif (! ref($g->{search_file})) {
		@searchfiles = $g->{search_file};
	}
	else {
		&{$g->{error_routine}}($g->{error_page},
			"{search_file} must be array reference or scalar.\n");
		$g->{matches} = -1;
		return undef; # If it makes it this far
	}

	local($/) = $g->{record_delim};

	foreach $searchfile (@searchfiles) {
		$searchfile = "$g->{base_directory}/$searchfile"
			unless ($searchfile =~ m:^/: || ! $g->{base_directory});
		open(Vend::TextSearch::SEARCH, $searchfile)
			or &{$g->{log_routine}}( "Couldn't open $searchfile: $!\n"), next;
		my $line;
		if(defined $g->{head_skip} and $g->{head_skip} > 0) {
			while(<Vend::TextSearch::SEARCH>) {
				last if $. >= $g->{head_skip};
			}
		}
		if($g->{dict_look}) {
#			$s->debug("Dict search:  look='$g->{dict_look}'");
#			$s->debug("Dict search:   end='$g->{dict_end}'");
			look \*Vend::TextSearch::SEARCH,
				$g->{dict_look}, $g->{dict_order}, $g->{dict_fold};
		}

		if(defined $limit_sub) {
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$f();
				next unless &$limit_sub($_);
				if($g->{return_file_name}) {
					push @out, $searchfile;
					last;
				}
				push @out, &$return_sub($_);
			}
		}
		elsif($g->{dict_end}) {
			while(<Vend::TextSearch::SEARCH>) {
				last if &$dict_limit($_);
#				$s->debug("Dict search: found='$_'");
				next unless &$f();
				if(defined $limit_sub) {
					next unless &$limit_sub($_);
				}
				if($g->{return_file_name}) {
					push @out, $searchfile;
					last;
				}
				push @out, &$return_sub($_);
			}
		}
		else {
			while(<Vend::TextSearch::SEARCH>) {
				next unless &$f();
				if($g->{return_file_name}) {
					push @out, $searchfile;
					last;
				}
				push @out, &$return_sub($_);
			}
		}
		close Vend::TextSearch::SEARCH;
	}

	$g->{matches} = scalar(@out);
	$g->{first_match} = 0;

	if ($g->{matches} > $g->{match_limit}) {
		$matches_to_send = $g->{match_limit};
		my $file;
		my $id = $g->{session_id} . ':' . $g->{search_mod};
		$g->{overflow} = 1;
		$g->{next_pointer} = $g->{match_limit};
		my $save = $s->save_context( @{$g->{'save_context'}} )
				if defined $g->{save_context};
		if($file = $g->{save_dir}) {
			$file .= '/' . $id;

			if(open(Vend::TextSearch::MATCHES, ">$file")) {
				(print Vend::TextSearch::MATCHES "~$id $save\n")
					if defined $save;
				chomp(@out);
				print Vend::TextSearch::MATCHES join "\n", @out;
				close Vend::TextSearch::MATCHES;
			}
			else {
				&{$g->{log_routine}}("search: Couldn't write $file: $!\n");
			}
		}
		elsif(ref $g->{save_hash}) {
			$g->{save_hash}->{"~$id"} = $save
					if defined $save;
			my $id = $g->{session_id} . ':' . $g->{search_mod};
			$g->{save_hash}->{$id} = join "\n", @out;
		}
	}
	else {
		$matches_to_send = $g->{matches};
		$g->{next_pointer} = 0;
	}

#	$s->debug($g->{matches}, " matches");
#	$s->debug("0 .. ", ($matches_to_send - 1));
	$s->save_history() if $g->{history};

	@out[0..($matches_to_send - 1)];
}

1;
__END__
