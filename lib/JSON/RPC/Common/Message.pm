#!/usr/bin/perl

package JSON::RPC::Common::Message;
BEGIN {
  $JSON::RPC::Common::Message::VERSION = '0.09';
}
use Moose::Role;
# ABSTRACT: JSON-RPC message role

use Carp qw(croak);

use namespace::clean -except => [qw(meta)];

requires 'deflate';

sub inflate {
	my ( $class, @args ) = @_;

	my $data;
	if (@args == 1) {
		if (defined $args[0]) {
			no warnings 'uninitialized';
			(ref($args[0]) eq 'HASH')
			|| confess "Single parameters to inflate() must be a HASH ref";
			$data = $args[0];
		}
	}
	else {
		$data = { @args };
	}

	my $subclass = $class->_version_class( $class->_get_version($data), $data );

	Class::MOP::load_class($subclass);

	$subclass->new_from_data(%$data);
}

sub new_from_data { shift->new(@_) }

sub _get_version {
	my ( $class, $data ) = @_;

	if ( exists $data->{jsonrpc} ) {
		return $data->{jsonrpc}; # presumably 2.0
	} elsif ( exists $data->{version} ) {
		return $data->{version}; # presumably 1.1
	} else {
		return "1.0";
	}
}

sub _version_class {
	my ( $class, $version, $data ) = @_;

	my @numbers = ( $version =~ /(\d+)/g ) ;

	if ( $class eq __PACKAGE__ and $data ) {
		if ( exists $data->{method} ) {
			$class = "JSON::RPC::Common::Procedure::Call";
		} elsif ( exists $data->{id} or exists $data->{result} ) {
			$class = "JSON::RPC::Common::Procedure::Return";
		} else {
			croak "Couldn't determine type of message (call or return)";
		}
	}

	return join( "::", $class, join("_", Version => @numbers) );
}

__PACKAGE__


__END__
=pod

=head1 NAME

JSON::RPC::Common::Message - JSON-RPC message role

=head1 VERSION

version 0.09

=head1 AUTHOR

Yuval Kogman <nothingmuch@woobling.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Yuval Kogman.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

