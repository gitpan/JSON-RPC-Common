#!/usr/bin/perl

package JSON::RPC::Common::Procedure::Call::Version_1_1;
use Moose;

use JSON::RPC::Common::TypeConstraints qw(JSONContainer);

use JSON::RPC::Common::Procedure::Return::Version_1_1;

use Carp qw(croak);

use namespace::clean -except => [qw(meta)];

extends qw(JSON::RPC::Common::Procedure::Call);

around new => sub {
	my $next = shift;
	my ( $self, @args ) = @_;

	my %data;
	if (@args == 1) {
		if (defined $args[0]) {
			no warnings 'uninitialized';
			(ref($args[0]) eq 'HASH')
			|| confess "Single parameters to new() must be a HASH ref";
			%data = %{$args[0]};
		}
	}
	else {
		%data = @args;
	}

	if ( exists $data{kwparams} ) {
		if ( exists $data{params} ) {
			croak "params and kwparams are mutuall exclusive";
		} else {
			$data{params} = delete $data{kwparams};
		}

		$data{alt_spec} = 1 unless exists $data{alt_spec};
	}

	$self->$next(%data);
};

has '+version' => (
	# default => "1.1", # broken, Moose::Meta::Method::Accessor gens numbers if looks_like_number
	default => sub { "1.1" },
);

has alt_spec => (
	isa => "Bool",
	is  => "rw",
	default => 0,
);

has '+params' => (
	isa => JSONContainer,
);

has '+return_class' => (
	default => "JSON::RPC::Common::Procedure::Return::Version_1_1",
);

has '+return_class' => (
	default => "JSON::RPC::Common::Procedure::Return::Version_1_1",
);

has '+error_class' => (
	default => "JSON::RPC::Common::Procedure::Return::Version_1_1::Error",
);

sub is_notification { 0 }

sub is_service {
	my $self = shift;
	$self->method =~ /^system\./;
}

sub deflate_version {
	my $self = shift;
	return ( version => $self->version ) ;
}

sub deflate_params {
	my $self = shift;

	if ( $self->has_params ) {
		my $params = $self->params;

		# JSON-RPC 1.1 alt specifies that named params go in kwparams. YUCK!
		if ( ref($params) eq 'HASH' and $self->alt_spec ) {
			return ( kwparams => $params );
		}

		return ( params => $params );
	} else {
		return ();
	}
}

__PACKAGE__->meta->make_immutable;

__PACKAGE__

__END__

=pod

=head1 NAME

JSON::RPC::Common::Procedure::Call::Version_1_1 - JSON-RPC 1.1 Procedure Call

=head1 SYNOPSIS

	use JSON::RPC::Common::Procedure::Call;

	my $req = JSON::RPC::Common::Procedure::Call->inflate({
		version => "1.1",
		id      => "oink",
		params  => { foo => "bar" },
	});

=head1 DESCRIPTION

This class implements JSON-RPC 1.1 Procedure Calls according to the 1.1 working
draft: L<http://json-rpc.org/wd/JSON-RPC-1-1-WD-20060807.html>.

JSON RPC 1.1 requests are never notifications, and accept either hash
references or array references as parameters.

Note that the alternative JSON RPC 1.1 proposition is also be supported:
L<http://groups.google.com/group/json-rpc/web/json-rpc-1-1-alt>. C<kwparams> is
accepted as an alias to C<params>, but C<params> will also accept hash
references. However, to simplify things, C<params> and C<kwparams> are mutually
exclusive, since Perl doesn't have strong support for named params.

The alternative spec does not offer notifications (it is a TODO item), so
currently C<is_notification> always returns false.

=cut

