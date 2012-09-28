package Dist::Zilla::Role::TravisYML;

# VERSION
# ABSTRACT: Role for .travis.yml creation

use sanity;

use Moose::Role;
use MooseX::Has::Sugar;
use MooseX::Types::Moose qw{ ArrayRef Str Bool is_Bool };

use List::AllUtils qw{ first sum };
use Acme::Indent qw(ai);  # no idea why this is Acme::
use File::Slurp;

use Module::CoreList;
use version 0.77;

requires 'zilla';
requires 'logger';

with 'Dist::Zilla::Role::MetaCPANInterfacer';

sub log       { shift->logger->log(@_)       }
sub log_debug { shift->logger->log_debug(@_) }
sub log_fatal { shift->logger->log_fatal(@_) }

### HACK: Need these rw for ChainSmoking ###
has build_branch  => ( rw, isa => Str,           default => '/^build\/.*/' );
has notify_email  => ( rw, isa => ArrayRef[Str], default => sub { [ 1 ] }  );
has notify_irc    => ( rw, isa => ArrayRef[Str], default => sub { [ 0 ] }  );
has mvdt          => ( rw, isa => Bool,          default => 0              );

has _header => ( ro, isa => Str, lazy, default => sub {
   ai('
      language: perl
      perl:
         - "5.16"
         - "5.14"
         - "5.12"
         - "5.10"
   ');
});
has _footer => ( ro, isa => Str, lazy, default => sub {
   my $self = shift;
   
   my $email = $self->notify_email->[0];
   my $irc   = $self->notify_irc->[0];
   my $zilla = $self->zilla;
   my $rmeta = $self->zilla->distmeta->{resources};
   
   no warnings 'numeric';  # *grumble*
   
   $irc == 1 and $irc = $self->notify_irc->[0] = $rmeta->{ first { /irc$/i } keys %$rmeta } || 0;
   s#^irc:|/+##gi for @{$self->notify_irc};
   
   my $footer = '';
   # Travis-CI default is to set email, but not use IRC
   unless ($email == 1 && !$irc) {
      $footer .=               "notifications:\n";
      $footer .= $email == 0 ? "   email: false\n" :
                 $email == 1 ? "" :
                               "   email:\n".join("\n", map { '      - "'.$_.'"'; } grep { $_ } @{$self->notify_email})."\n";
      $footer .= "   irc:\n".
                 "      channels:\n".
                 join("\n", map { '         - "'.$_.'"'; } grep { $_ } @{$self->notify_irc })."\n".
                 "      template:\n".
                 '         - "%{branch}#%{build_number} by %{author}: %{message} (%{build_url})'."\n".
                 "      on_success: change\n".
                 "      on_failure: always\n".
                 "      use_notice: true\n"
         if ($irc);
   }
   
   return $footer;
});

has _releases => ( ro, isa => ArrayRef[Str], lazy, default => sub {
   my $self = shift;

   # Find the lowest required dependencies and tell Travis-CI to install them
   my @releases;
   if ($self->mvdt) {
      my $prereqs = $self->zilla->prereqs;
      $self->log("Searching for minimum dependency versions");
      
      my $minperl = version->parse(
         $prereqs->requirements_for('runtime', 'requires')->requirements_for_module('perl') ||
         v5.8.8  # released in 2006... C'mon, people!  Don't make me lower this!
      );
      foreach my $phase (qw(runtime configure build test)) {
         $self->logger->set_prefix("{Phase '$phase'} ");
         my $req = $prereqs->requirements_for($phase, 'requires');
         
         foreach my $module ( sort ($req->required_modules) ) {
            next if $module eq 'perl';  # obvious

            my $modver = $req->requirements_for_module($module);
            my ($release, $minver) = $self->_mcpan_module_minrelease($module, $modver);
            next unless $release;
            my $mod_in_perlver = Module::CoreList->first_release($module, $minver);
            
            if ($mod_in_perlver && $minperl >= $mod_in_perlver) {
               $self->log_debug(['Module %s v%s is already found in core Perl v%s (<= v%s)', $module, $minver, $mod_in_perlver, $minperl]);
               next;
            }
            
            $self->log_debug(['Found minimum dep version for Module %s as %s', $module, $release]);
            push @releases, $release;
         }
      }
      $self->logger->clear_prefix;
   }
   
   return \@releases;
});

sub build_travis_yml {
   my ($self, $is_build_branch) = @_;
   
   my $header   = $self->_header;
   my $footer   = $self->_footer;
   my @releases = @{$self->_releases};

   my $env_vars = '   - export RELEASE_TESTING=1 AUTOMATED_TESTING=1 AUTHOR_TESTING=1 HARNESS_OPTIONS=j10:c HARNESS_TIMER=1';
   unless ($is_build_branch) {
      my $install = join ("\n", scalar(@releases) ? (
         '   # Install the lowest possible required version for the dependencies',
         $env_vars,
         '   - export OLD_CPANM_OPT=$PERL_CPANM_OPT',
         "   - export PERL_CPANM_OPT='--mirror http://cpan.metacpan.org/ --mirror http://search.cpan.org/CPAN '\$PERL_CPANM_OPT",
         (map { '   - cpanm --verbose '.$_ } @releases),
         '   - export PERL_CPANM_OPT=$OLD_CPANM_OPT',
      ) : (
         $env_vars,
         "   - dzil listdeps | grep -vP '[^\\w:]' | cpanm --verbose"
      ) );

      File::Slurp::write_file( '.travis.yml', join("\n",
         $header,
         ai("
            install:
               # Deal with all of the DZIL dependancies, quickly and quietly
               - cpanm --quiet --notest --skip-satisfied Dist::Zilla
               - dzil authordeps | grep -vP '[^\\w:]' | xargs -n 5 -P 10 cpanm --quiet --notest --skip-satisfied
         "),
         $install,
         'script:',
         '   - dzil smoke --release --author',
         $footer,
      ) );
   }
   elsif (my $bbranch = $self->build_branch) {
      my $install = join ("\n", scalar(@releases) ? (
         'install:',
         '   # Install the lowest possible required version for the dependencies',
         $env_vars,
         '   - export OLD_CPANM_OPT=$PERL_CPANM_OPT',
         "   - export PERL_CPANM_OPT='--mirror http://cpan.metacpan.org/ --mirror http://search.cpan.org/CPAN '\$PERL_CPANM_OPT",
         (map { '   - cpanm --verbose '.$_ } @releases),
         '   - export PERL_CPANM_OPT=$OLD_CPANM_OPT',
      ) : (
         'install:',
         $env_vars,
         '   - cpanm --installdeps --notest --skip-satisfied .',
      ) );

      File::Slurp::write_file(
         Path::Class::File->new($self->zilla->built_in, '.travis.yml')->stringify,
         join("\n",
            $header,
            'before_install:',
            '   # Prevent any test problems with this file',
            '   - rm .travis.yml',
            $install,
            '',
            ai("
               # whitelist
               branches:
                  only:
                    - $bbranch
            "),
            $footer,
         )
      );
   }
}

sub _as_lucene_query {
   my ($self, $ver_str) = @_;
   
   # simple versions short-circuits
   return () if $ver_str eq '0';
   return ('module.version_numified:['.version->parse($ver_str)->numify.' TO 999999]')
      unless ($ver_str =~ /[\<\=\>]/);
   
   my ($min, $max, $is_min_inc, $is_max_inc, @num_conds, @str_conds);
   foreach my $ver_cmp (split(qr{\s*,\s*}, $ver_str)) {
      my ($cmp, $ver) = split(qr{(?<=[\<\=\>])\s*(?=\d)}, $ver_cmp, 2);
      
      # Normalize string, but keep originals for alphas
      my $use_num = 1;
      my $orig_ver = $ver;
      $ver = version->parse($ver);
      my $num_ver = $ver->numify;
      if ($ver->is_alpha) {
         $ver = $orig_ver;
         $ver =~ s/^v//i;
         $use_num = 0;
      }
      else { $ver = $num_ver; }
      
      for ($cmp) {
         when ('==') { return 'module.version'.($use_num ? '_numified' : '').':'.$ver; }  # no need to look at anything else
         when ('!=') { $use_num ? push(@num_conds, '-'.$ver) : push(@str_conds, '-'.$ver); }
         ### XXX: Trying to do range-based searches on strings isn't a good idea, so we always use the number field ###
         when ('>=') { ($min, $is_min_inc) = ($num_ver, 1); }
         when ('<=') { ($max, $is_max_inc) = ($num_ver, 1); }
         when ('>')  { ($min, $is_min_inc) = ($num_ver, 0); }
         when ('<')  { ($max, $is_max_inc) = ($num_ver, 0); }
         default     { die 'Unable to parse complex module requirements with operator of '.$cmp.' !'; }
      }
   }
   
   # Min/Max parsing
   if ($min || $max) {
      $min ||= 0;
      $max ||= 999999;
      my $rng = $min.' TO '.$max;
      
      # Figure out the inclusive/exclusive status
      my $inc = $is_min_inc.$is_max_inc;  # (this is just easier to deal with as a combined form)
      unshift @num_conds, '-'.($inc eq '01' ? $min : $max)
         if ($inc =~ /0/ && $inc =~ /\d\d/);  # has mismatch of inc/exc (reverse order due to unshift)
      unshift @num_conds, '+'.($inc =~ /1/ ? '['.$rng.']' : '{'.$rng.'}');  # +[{ $min TO $max }]
   }
   
   # Create the string
   my @lq;
   push @lq, 'module.version_numified:('.join(' ', @num_conds).')' if @num_conds;
   push @lq, 'module.version:('         .join(' ', @str_conds).')' if @str_conds;
   return @lq;
}

sub _mcpan_module_minrelease {
   my ($self, $module, $ver_str, $try_harder) = @_;
  
   my @lq = $self->_as_lucene_query($ver_str);
   my $maturity_q = ($ver_str =~ /==/) ? undef : 'maturity:released';  # exact version may be a developer one
   
   ### XXX: This should be replaced with a ->file() method when those
   ### two pull requests of mine are put into CPAN...
   my $q = join(' AND ', 'module.name:"'.$module.'"', $maturity_q, 'module.authorized:true', @lq);
   $self->log_debug("Checking module $module via MetaCPAN");
   #$self->log_debug("   [q=$q]");
   my $details = $self->mcpan->fetch("file/_search",
      q      => $q,
      sort   => 'module.version_numified',
      fields => 'author,release,module.version,module.name',
      size   => $try_harder ? 20 : 1,
   );
   unless ($details && $details->{hits}{total}) {
      $self->log("??? MetaCPAN can't even find a good version for $module!");
      return undef;
   }

   # Sometimes, MetaCPAN just gets highly confused...
   my @hits = @{ $details->{hits}{hits} };
   my $hit;
   my $is_bad = 1;
   do {
      $hit = shift @hits;
      # (ie: we shouldn't have multiples of modules or versions, and sort should actually have a value)
      $is_bad = !$hit->{sort}[0] || ref $hit->{fields}{'module.name'} || ref $hit->{fields}{'module.version'};
   } while ($is_bad and @hits);
   
   if ($is_bad) {
      if ($try_harder) {
         $self->log("??? MetaCPAN is highly confused about $module!");
         return undef;
      }
      $self->log_debug("   MetaCPAN got confused; trying harder...");
      return $self->_mcpan_module_minrelease($module, $ver_str, 1)
   }
   
   $hit = $hit->{fields};
   
   # This will almost always be .tar.gz, but TRIAL versions might have different names, etc.
   my $fields = $self->mcpan->release(
      search => {
         q      => 'author:'.$hit->{author}.' AND name:"'.$hit->{release}.'"',
         fields => 'archive,tests',
         size   => 1,
      },
   )->{hits}{hits}[0]{fields};

   # Warn about test failures
   my $t = $fields->{tests};
   my $ttl = sum @$t{qw(pass fail unknown na)};
   unless ($ttl) {
      $self->log(['%s has no CPAN test results!  You should consider upgrading the minimum dep version for %s...', $hit->{release}, $module]);   
   }
   else {
      my $per   = $t->{pass} / $ttl * 100;
      my $f_ttl = $ttl - $t->{pass};
      
      if ($per < 70 || $t->{fail} > 20 || $f_ttl > 30) {
         $self->log(['CPAN Test Results for %s:', $hit->{release}]);
         $self->log(['   %7s: %4u (%3.1f)', $_, $t->{lc $_}, $t->{lc $_} / $ttl * 100]) for (qw(Pass Fail Unknown NA));
         $self->log(['You should consider upgrading the minimum dep version for %s...', $module]);
      }
   }
   
   my $v = $hit->{'module.version'};
   return ($hit->{author}.'/'.$fields->{archive}, $v && version->parse($v));
}

42;
 
__END__