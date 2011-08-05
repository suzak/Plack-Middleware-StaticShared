package Plack::Middleware::StaticShared;
use strict;
use warnings;

use parent qw(Plack::Middleware);
use Digest::SHA1 qw(sha1_hex);
use DateTime::Format::HTTP;
use DateTime;
use Plack::Util;

our $VERSION = '0.02';

use Plack::Util::Accessor qw(cache binds verifier);

sub call {
	my ($self, $env) = @_;
	for my $static (@{ $self->binds }) {
		my $prefix = $static->{prefix};
		# Some browsers (eg. Firefox) always access if the url has query string,
		# so use `:' for parameters
		my ($version, $files) = ($env->{PATH_INFO} =~ /^$prefix:([^:\s]{1,32}):(.+)$/) or next;
		if ($self->verifier && !$self->verifier->(local $_ = $version, $prefix)) {
			return [400, [ ], [ ]];
		}

		my $key = join(':', $version, $files);
		my $etag = sha1_hex($key);

		if (($env->{HTTP_IF_NONE_MATCH} || '') eq $etag) {
			# Browser cache is avaialable but force reloaded by user.
			return [304, [ ], [ ]];
		}
		my $content = eval {
			my $ret = $self->cache->get($key);
			if (not defined $ret) {
				$ret = $self->concat($env, split /,/, $files);
				$ret = $static->{filter}->(local $_ = $ret) if $static->{filter};
				$self->cache->set($key => $ret);
			}
			$ret;
		};

		return [503, ['Retry-After' => 10], [ $@ ]] if $@;

		# Cache control:
		# IE requires both Last-Modified and Etag to ignore checking updates.
		return [200, [
			"Cache-Control" => "public; max-age=315360000; s-maxage=315360000",
			"Expires" => DateTime::Format::HTTP->format_datetime(DateTime->now->add(years => 10)),
			"Last-Modified" => DateTime::Format::HTTP->format_datetime(DateTime->from_epoch(epoch => 0)),
			"ETag" => $etag,
			"Content-Type" => $static->{content_type},
		], [ $content ]];
	}

	$self->app->($env);
}

sub concat {
	my ($self, $env, @files) = @_;
	return join '', map {
		local $env->{PATH_INFO} = $_;
		my $res = $self->app->($env);
		ref $res eq 'ARRAY' && $res->[0] == 200 ? do {
			my $static;
			Plack::Util::foreach($res->[2], sub { $static .= $_[0] });
			$static;
		} : '';
	} @files;
}

1;
__END__

1;
__END__

=head1 NAME

Plack::Middleware::StaticShared - concat some static files to one resource

=head1 SYNOPSIS

  use Plack::Builder;
  use WebService::Google::Closure;

  builder {
      enable "StaticShared",
          cache => Cache::Memcached::Fast->new(servers => [qw/192.168.0.11:11211/]),
          base  => './static/',
          binds => [
              {
                  prefix       => '/.shared.js',
                  content_type => 'text/javascript; charset=utf8',
                  filter       => sub {
                      WebService::Google::Closure->new(js_code => $_)->compile->code;
                  }
              },
              {
                  prefix       => '/.shared.css',
                  content_type => 'text/css; charset=utf8',
              }
          ];
          verifier => sub {
              my ($version, $prefix) = @_;
              $version =~ /v\d/
          },

      $app;
  };

And concatnated resources are provided as like following:

  /.shared.js:v1:/js/foolib.js,/js/barlib.js,/js/app.js
      => concat following: ./static/js/foolib.js, ./static/js/barlib.js, ./static/js/app.js

=head1 DESCRIPTION

Plack::Middleware::StaticShared provides resource end point which concat some static files to one resource for reducing http requests.

=head1 CONFIGURATIONS

=over 4

=item cache (required)

A cache object for caching concatnated resource content.

=item base (required)

Base directory which concatnating resource located in.

=item binds (required)

Definition of concatnated resources.

=item verifier (optional)

A subroutine for verifying version string to avoid attacking of cache flooding.

=back

=head1 AUTHOR

cho45

=head1 SEE ALSO

L<Plack::Middleware> L<Plack::Builder>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

