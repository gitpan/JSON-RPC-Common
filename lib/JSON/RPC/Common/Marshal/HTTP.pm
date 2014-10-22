#!/usr/bin/perl

package JSON::RPC::Common::Marshal::HTTP;
use Moose;

use Carp qw(croak);

use URI::QueryParam;

use namespace::clean -except => [qw(meta)];

extends qw(JSON::RPC::Common::Marshal::Text);

has prefer_encoded_get => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

has expand => (
	isa => "Bool",
	is  => "rw",
	default => 0,
);

has expander => (
	isa => "ClassName|Object",
	lazy_build => 1,
	handles => [qw(expand_hash)],
);

has content_type => (
	isa => "Str",
	is  => "rw",
	default => "application/json",
);

sub _build_expander {
	require CGI::Expand;
	return "CGI::Expand";
}

sub request_to_call {
	my ( $self, $request, @args ) = @_;

	my $req_method = lc( "request_to_call_" . $request->method );

	if ( my $code = $self->can($req_method) ) {
		$self->$code($request, @args);
	} else {
		croak "Unsupported HTTP request method " . $request->method;
	}
}

sub request_to_call_get {
	my ( $self, $request, @args ) = @_;

	my $uri = $request->uri;

	my %rpc;

	my $params = $uri->query_form_hash;

	if ( exists $params->{params} and $self->prefer_encoded_get ) {
		return $self->request_to_call_get_encoded( $request, $params, @args );
	} else {
		return $self->request_to_call_get_query( $request, $params, @args );
	}
}

# the sane way, 1.1-alt
sub request_to_call_get_encoded {
	my ( $self, $request, $params, @args ) = @_;

	# the 'params' URI param is encoded as JSON, inflate it
	my %rpc = %$params;
	$_ = $self->decode($_) for $rpc{params};

	$self->inflate_call(\%rpc);
}

# the less sane but occasionally useful way, 1.1-wd
sub request_to_call_get_query {
	my ( $self, $request, $params, @args  ) = @_;

	my %rpc = ( params => $params );

	foreach my $key (qw(version jsonrpc method id)) {
		if ( exists $params->{$key} ) {
			$rpc{$key} = delete $params->{$key};
		}
	}

	croak "JSON-RPC 1.0 is not supported on HTTP GET"
		unless ( ( $rpc{jsonrpc} || $rpc{version} || 0 ) >= 1.1 );

	# increases usefulness
	$rpc{params} = $self->process_query_params($params, $request, @args);

	$self->inflate_call(\%rpc);
}

sub process_query_params {
	my ( $self, $params, $request, @args ) = @_;

	if ( $self->expand ) {
		return $self->expand_hash($params);
	} else {
		return $params;
	}
}

sub request_to_call_post {
	my ( $self, $request ) = @_;
	$self->json_to_call( $request->content );
}

sub write_result_to_response {
	my ( $self, $result, $response, @args ) = @_;

	my %args = $self->result_to_response_params($result);

	foreach my $key ( keys %args ) {
		if ( $response->can($key) ) {
			$response->$key(delete $args{$key});
		}
	}

	croak "BAH" if keys %args;

	return 1;
}

sub response_to_result {
	my ( $self, $response ) = @_;

	if ( $response->is_success ) {
		$self->response_to_result_success($response);
	} else {
		$self->response_to_result_error($response);
	}
}

sub response_to_result_success {
	my ( $self, $response ) = @_;

	$self->json_to_return( $response->content );
}

sub response_to_result_error {
	my ( $self, $response ) = @_;

	my $res = $self->json_to_return( $response->content );

	unless ( $res->has_error ) {
		$res->set_error(
			message => $response->message,
			code    => $response->code, # FIXME dictionary
			data    => {
				response => $response,
			}
		);
	}

	return $res;
}

sub result_to_response {
	my ( $self, $result ) = @_;

	$self->create_http_response( $self->result_to_response_params($result) );
}

sub create_http_response {
	my ( $self, %args ) = @_;

	HTTP::Response->new(
		$args{status},
		undef,
		{ "Content-Type" => $args{content_type} },
		$args{body},
	);
}

sub result_to_response_params {
	my ( $self, $result ) = @_;

	return (
		status       => ( $result->has_error ? $result->error->http_status : 200 ),
		content_type => $self->content_type, # FIXME json-rpc for 1.1-alt and 2.0?
		body         => $self->encode($result->deflate),
	);
}

__PACKAGE__->meta->make_immutable();

__PACKAGE__

__END__

=pod

=head1 NAME

JSON::RPC::Common::Marshall::HTTP - COnvert L<HTTP::Request> and
L<HTTP::Response> to/from L<JSON::RPC::Common> calls and returns.

=head1 SYNOPSIS

	use JSON::RPC::Common::Marshall::HTTP;

	my $m = JSON::RPC::Common::Marshal::HTTP->new;

	my $call = $m->request_to_call($http_request);

	my $res = $call->call($object);

	my $http_response = $m->result_to_response($res);

=head1 DESCRIPTION

This object provides marshalling routines to convert calls and returns to and
from L<HTTP::Request> and L<HTTP::Response> objects.

=item ATTRIBUTES

=over 4

=item prefer_encoded_get

When set and a C<params> param exists, decode it as Base 64 encoded JSON and
use that as the parameters instead of the query parameters.

See L<http://json-rpc.googlegroups.com/web/json-rpc-over-http.html>.

B<TODO> Currently buggy, no base 64 decoding is implemented. The spec is shit
anyway.

=item content_type

Defaults to C<application/json>.

B<TODO> In the default the this class will choose the correct content type
based on the spec in the future if one is not set explicitly.

=item expand

Whether or not to use an expander on C<GET> style calls.

=item expander

An instance of L<CGI::Expand> or a look alike to use for C<GET> parameter
expansion.

=back

=head1 METHODS

=over 4

=item request_to_call

=item request_to_call_post

=item request_to_call_get

=item request_to_call_get_encoded

=item request_to_call_get_query

Convert an L<HTTP::Request> to a L<JSON::RPC::Common::Procedure::Call>.
Depending on what style of request it is, C<request_to_call> will delegate to a
variant.

=item result_to_response

Convert a L<JSON::RPC::Common::Procedure::Return> to an L<HTTP::Response>.

=item response_to_result

=item response_to_result_success

=item response_to_result_error

Convert an L<HTTP::Response> to a L<JSON::RPC::Common::Procedure::Return>.

A variant is chosen based on C<HTTP::Response/is_success>.

The error handler will ensure that
L<JSON::RPC::Common::Procedure::Return/error> is set.

=back

=head1 TODO

Conversion of L<JSON::RPC::Common::Procedure::Call> to L<HTTP::Request> is not
yet implemented.

This should be fairly trivial but I'm a lazy bastard.

=cut


