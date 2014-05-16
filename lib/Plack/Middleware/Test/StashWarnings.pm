package Plack::Middleware::Test::StashWarnings;

use strict;
use 5.008_001;
our $VERSION = '0.08';

use parent qw(Plack::Middleware);
use Carp ();
use Storable 'nfreeze';

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $self = $class->SUPER::new(@_);
    $self->{verbose} = $ENV{TEST_VERBOSE} unless defined $self->{verbose};
    return $self;
}

sub call {
    my ($self, $env) = @_;

    if ($env->{PATH_INFO} eq '/__test_warnings') {
        Carp::carp("Use a single process server like Standalone to run Test::StashWarnings middleware")
            if $env->{'psgi.multiprocess'} && $self->{multiprocess_warn}++ == 0;

        return [ 200, ["Content-Type", "application/x-storable"], [ $self->dump_warnings ] ];
    }

    my $ret = $self->_stash_warnings_for($self->app, $env);

    # for the streaming API, we need to re-instate the dynamic sigwarn handler
    # around the streaming callback
    if (ref($ret) eq 'CODE') {
        return sub { $self->_stash_warnings_for($ret, @_) };
    }

    return $ret;
}

sub _stash_warnings_for {
    my $self = shift;
    my $code = shift;

    my $old_warn = $SIG{__WARN__} || sub { warn @_ };
    local $SIG{__WARN__} = sub {
        $self->add_warning(@_);
        $old_warn->(@_) if $self->{verbose};
    };

    return $code->(@_);
}

sub add_warning {
    my $self = shift;
    push @{ $self->{stashed_warnings} }, @_;
}

sub dump_warnings {
    my $self = shift;

    return nfreeze([ splice @{ $self->{stashed_warnings} } ]);
}

sub DESTROY {
    my $self = shift;
    for (splice @{ $self->{stashed_warnings} }) {
        warn "Unhandled warning: $_";
    }
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Plack::Middleware::Test::StashWarnings - Test your application's warnings

=head1 SYNOPSIS

  # for your PSGI application:
  enable "Test::StashWarnings";


  # for your Test::WWW::Mechanize subclass:
  use Storable 'thaw';
  sub get_warnings {
      local $Test::Builder::Level = $Test::Builder::Level + 1;
      my $self = shift;
  
      my $clone = $self->clone;
      return unless $clone->get_ok('/__test_warnings');
  
      my @warnings = @{ thaw $clone->content };
      return @warnings;
  }

=head1 DESCRIPTION

Plack::Middleware::Test::StashWarnings is a Plack middleware component to
record warnings generated by your application so that you can test them to make
sure your application complains about the right things.

The warnings generated by your application are available at a special URL
(C</__test_warnings>), encoded with L<Storable/nfreeze>. So using
L<Test::WWW::Mechanize> you can just C<get> that URL and L<Storable/thaw> its
content.

=head1 ARGUMENTS

Plack::Middleware::Test::StashWarnings takes one optional argument,
C<verbose>, which defaults to C<$ENV{TEST_VERBOSE}>.  If set to true, it
will bubble warnings up to any pre-existing C<__WARN__> handler.
Turning this explicitly off may be useful if your tests load
L<Test::NoWarnings> and also use L<Test::WWW::Mechanize::PSGI> for
non-forking testing -- failure to do so would result in test failures
even for caught warnings.

=head1 RATIONALE

Warnings are an important part of any application. Your web application should
warn its operators when something is amiss.

Almost as importantly, your web application should gracefully cope with bad
input, the back button, and all other aspects of the user experience.

Unfortunately, tests seldom cover what happens when things go poorly. Are you
I<sure> that your application correctly denies that action and logs the
failure? Are you I<sure> it will tomorrow?

This module lets you retrieve the warnings that your forked server issues. That
way you can test that your application continues to issue warnings when it
makes sense. Catching the warnings also keeps your test output tidy. Finally,
you'll be able to see (and be notified via failing tests) when your
application issues new, unexpected warnings so you can fix them immediately.

=head1 AUTHOR

Shawn M Moore C<sartak@bestpractical.com>

Tatsuhiko Miyagawa wrote L<Plack::Middleware::Test::Recorder> which served as
a model for this module.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Test::HTTP::Server::Simple::StashWarnings>

=cut
