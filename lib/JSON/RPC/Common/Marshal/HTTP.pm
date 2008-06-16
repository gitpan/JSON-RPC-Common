#!/usr/bin/perl

package JSON::RPC::Common::Marshal::HTTP;
use Moose;

use Carp qw(croak);

use URI::QueryParam;
use MIME::Base64 ();

use namespace::clean -except => [qw(meta)];

extends qw(JSON::RPC::Common::Marshal::Text);

has prefer_get => (
	isa => "Bool",
	is  => "rw",
	default => 0,
);

has rest_style_methods => (
	isa => "Bool",
	is  => "rw",
	default => 1,
);

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
	handles => [qw(expand_hash collapse_hash)],
);

sub _build_expander {
	require CGI::Expand;
	return "CGI::Expand";
}


has user_agent => (
	isa => "Str",
	is  => "rw",
	lazy_build => 1,
);

sub _build_user_agent {
	my $self = shift;
	require JSON::RPC::Common;
	join(" ", ref($self), $JSON::RPC::Common::VERSION),
}

has content_type => (
	isa => "Str",
	is  => "rw",
	predicate => "has_content_type",
);

has content_types => (
	isa => "HashRef[Str]",
	is  => "rw",
	lazy_build => 1,
);

sub _build_content_types {
	return {
		"1.0" => "application/json",
		"1.1" => "application/json",
		"2.0" => "application/json-rpc",
	};
}

has accept_content_type => (
	isa => "Str",
	is  => "rw",
	predicate => "has_accept_content_type",
);

has accept_content_types => (
	isa => "HashRef[Str]",
	is  => "rw",
	lazy_build => 1,
);

sub _build_accept_content_types {
	return {
		"1.0" => "application/json",
		"1.1" => "application/json",
		"2.0" => "application/json-rpc",
	};
}

sub get_content_type {
	my ( $self, $obj ) = @_;

	if ( $self->has_content_type ) {
		return $self->content_type;
	} else {
		return $self->content_types->{ $obj->version || "2.0" };
	}
}

sub get_accept_content_type {
	my ( $self, $obj ) = @_;

	if ( $self->has_accept_content_type ) {
		return $self->accept_content_type;
	} else {
		return $self->accept_content_types->{ $obj->version || "2.0" };
	}
}

sub call_to_request {
	my ( $self, $call, %args ) = @_;

	$args{prefer_get} = $self->prefer_get unless exists $args{prefer_get};

	if ( $args{prefer_get} ) {
		return $self->call_to_get_request($call, %args);
	} else {
		return $self->call_to_post_request($call, %args);
	}
}

sub call_to_post_request {
	my ( $self, $call, %args ) = @_;

	my $uri = $args{uri} || URI->new("/");

	my $encoded = $self->call_to_json($call);

	my $headers = HTTP::Headers->new(
		User_Agent     => $self->user_agent,
		Content_Type   => $self->get_content_type($call),
		Accept         => $self->get_accept_content_type($call),
		Content_Length => length($encoded),
	);

	return HTTP::Request->new( POST => $uri, $headers, $encoded );
}

sub call_to_get_request {
	my ( $self, $call, @args ) = @_;

	my $uri = $self->call_to_uri($call, @args);

	my $headers = HTTP::Headers->new(
		User_Agent     => $self->user_agent,
		Accept         => $self->get_accept_content_type($call),
	);

	HTTP::Request->new( GET => $uri, $headers );
}

sub call_to_uri {
	my ( $self, $call, %args ) = @_;

	no warnings 'uninitialized';
	my $prefer_encoded_get = exists $args{encoded}
		? $args{encoded}
		: ( $call->version eq '2.0' || $self->prefer_encoded_get );

	if ( $prefer_encoded_get ) {
		return $self->call_to_encoded_uri($call, %args);
	} else {
		return $self->call_to_query_uri($call, %args);
	}
}

sub call_to_encoded_uri {
	my ( $self, $call, %args ) = @_;

	my $uri = $args{uri} ? $args{uri}->clone : URI->new("/");

	my $deflated = $self->deflate_call($call);

	my ( $method, $params, $id ) = delete @{ $deflated }{qw(method params id)};

	my $encoded = $self->encode_base64( $self->encode($params) );

	$uri->query_param( params => $encoded );
	$uri->query_param( method => $method );
	$uri->query_param( id => $id ) if $call->has_id;

	return $uri;
}

sub call_to_query_uri {
	my ( $self, $call, %args ) = @_;

	my $uri = $args{uri} ? $args{uri}->clone : URI->new("/");

	my $deflated = $self->deflate_call( $call );

	my ( $method, $params, $id ) = delete @{ $deflated }{qw(method params id)};

	$params = $self->collapse_query_params($params);

	$uri->query_form( %$params, id => $id );

	if ( $self->rest_style_methods ) {
		my $path = $uri->path;
		$path =~ s{/?$}{"/" . $method}e; # add method, remove double trailing slash
		$uri->path($path);
	} else {
		$uri->query_param( method => $method );
	}

	return $uri;
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

sub decode_base64 {
	my ( $self, $base64 ) = @_;
	MIME::Base64::decode_base64($base64);
}

sub encode_base64 {
	my ( $self, $base64 ) = @_;
	MIME::Base64::encode_base64($base64);
}

# the sane way, 1.1-alt
sub request_to_call_get_encoded {
	my ( $self, $request, $params, @args ) = @_;

	# the 'params' URI param is encoded as JSON, inflate it
	my %rpc = %$params;

	$rpc{version} ||= "2.0";

	for my $params ( $rpc{params} ) {
		# try as unencoded JSON first
		if ( my $data = do { local $@; eval { $self->decode($params) } } ) {
			$params = $data;
		} else {
			my $json = $self->decode_base64($params) || croak "params are not Base64 encoded";
			$params = $self->decode($json);
		}
	}

	$self->inflate_call(\%rpc);
}

# the less sane but occasionally useful way, 1.1-wd
sub request_to_call_get_query {
	my ( $self, $request, $params, @args  ) = @_;

	my %rpc = ( params => $params );

	foreach my $key (qw(version jsonrpc method id) ) {
		if ( exists $params->{$key} ) {
			$rpc{$key} = delete $params->{$key};
		}
	}

	if ( !exists($rpc{method}) and $self->rest_style_methods ) {
		my ( $method ) = ( $request->uri->path =~ m{/(\w+)$} );
		$rpc{method} = $method;
	}

	$rpc{version} ||= "1.1";

	# increases usefulness
	$rpc{params} = $self->expand_query_params($params, $request, @args);

	$self->inflate_call(\%rpc);
}

sub expand_query_params {
	my ( $self, $params, $request, @args ) = @_;

	if ( $self->expand ) {
		return $self->expand_hash($params);
	} else {
		return $params;
	}
}

sub collapse_query_params {
	my ( $self, $params, $request, @args ) = @_;

	if ( $self->expand ) {
		return $self->collapse_hash($params);
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
		HTTP::Headers->new( Content_Type => $args{content_type} ),
		$args{body},
	);
}

sub result_to_response_params {
	my ( $self, $result ) = @_;

	return (
		status       => ( $result->has_error ? $result->error->http_status : 200 ),
		content_type => $self->get_content_type($result),
		body         => $self->encode($result->deflate),
	);
}

__PACKAGE__->meta->make_immutable();

__PACKAGE__

__END__

=pod

=head1 NAME

JSON::RPC::Common::Marshal::HTTP - Convert L<HTTP::Request> and
L<HTTP::Response> to/from L<JSON::RPC::Common> calls and returns.

=head1 SYNOPSIS

	use JSON::RPC::Common::Marshal::HTTP;

	my $m = JSON::RPC::Common::Marshal::HTTP->new;

	my $call = $m->request_to_call($http_request);

	my $res = $call->call($object);

	my $http_response = $m->result_to_response($res);

=head1 DESCRIPTION

This object provides marshalling routines to convert calls and returns to and
from L<HTTP::Request> and L<HTTP::Response> objects.

=item ATTRIBUTES

=over 4

=item prefer_get

When encoding a call into a request, prefer GET.

Not reccomended.

=item rest_style_methods

When encoding a GET request, use REST style URI formatting (the method is part
of the path, not a parameter).

=item prefer_encoded_get

When set and a C<params> param exists, decode it as Base 64 encoded JSON and
use that as the parameters instead of the query parameters.

See L<http://json-rpc.googlegroups.com/web/json-rpc-over-http.html>.

=item user_agent

Defaults to the marshal object's class name and the L<JSON::RPC::Common>
version number.

=item content_type

=item accept_content_type

=item content_types

=item accept_content_types

When explicitly set these are the values of the C<Content-Type> and C<Accept>
headers to set.

Otherwise they will default to C<application/json> with calls/returns version
1.0 and 1.1, and C<application/json-rpc> with 2.0 objects.

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

=item call_to_request $call, %args

=item call_to_get_request $call, %args

=item call_to_post_request $call, %args

=item call_to_uri $call, %args

=item call_to_encoded_uri $call, %args

=item call_to_query_uri $call, %args

Convert a call to a request (or just a URI for GET requests).

The arguments can contain a C<uri> parameter, which is the base of the request.

With GET requests, under C<rest_style_methods> that URI's path will be
appended, and otherwise parameters will just be added.

POST requests do not cloen and alter the URI.

If no URI is provided as an argument, C</> will be used.

The flags C<prefer_get> and C<encoded> can also be passed to
C<call_to_request> to alter the type of request to be generated.

=item result_to_response $result

=item write_result_to_response $result, $response

Either create an L<HTTP::Response> or write the result into an object like
L<Catalyst::Response>.

=item collapse_query_params

=item expand_query_params

Only used for query encoded GET requests. If C<expand> is set will cause
expansion of the params. Otherwise it's a noop.

Subclass and override to process query params into RPC params as necessary.

Note that this is B<NOT> in any of the JSON-RPC specs.

=back

=cut

