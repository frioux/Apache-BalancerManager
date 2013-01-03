package Apache::BalancerManager;

# ABSTRACT: Interact with the Apache BalancerManager

use Moo;
use List::Util ();
use Web::Scraper;

has url => (
   is => 'ro',
   required => 1,
);

has name => (
   is => 'ro',
   lazy => 1,
   builder => '_build_name',
);

sub _build_name {
   my $ret = $_[0]->_scraped_content->{name_stuff};

   $ret =~ s(^LoadBalancer Status for balancer://)();

   return $ret
}

has nonce => (
   is => 'ro',
   init_arg => undef,
   lazy => 1,
   builder => '_build_nonce',
);

sub _build_nonce {
   my $self = shift;

   my $url  = $self->url;
   my $link = $self->_scraped_content->{data}[0]{link};

   require URI;
   require URI::QueryParam;
   my $uri = URI->new("$url$link");
   scalar $uri->query_param('nonce')
}

has _index_content => (
   is => 'ro',
   init_arg => undef,
   lazy => 1,
   builder => '_build_index_content',
);

sub _build_index_content {
   my $self = shift;

   my $response = $self->_get($self->url);
   if ($response->is_success) {
       return $response->decoded_content;
   }
   else {
       die $response->status_line;
   }
}

has _scraper => (
   is => 'ro',
   init_arg => undef,
   lazy => 1,
   builder => '_build_scraper',
   handles => {
      _scrape => 'scrape',
   },
);

sub _build_scraper {
   return scraper {
      process 'h3', name_stuff => 'TEXT';
      process '//table[2]/tr' => 'data[]' => scraper {
         process '//td[1]/a/@href', 'link' => 'TEXT';
         process '//td[1]/a', 'location' => 'TEXT';
         process '//td[2]', 'route' => 'TEXT';
         process '//td[3]', 'route_redirect' => 'TEXT';
         process '//td[4]', 'load_factor' => 'TEXT';
         process '//td[5]', 'lb_set' => 'TEXT';
         process '//td[6]', status => 'TEXT';
         process '//td[7]', times_elected => 'TEXT';
         process '//td[8]', to => 'TEXT';
         process '//td[9]', from => 'TEXT';
      };
   };
}

has _scraped_content => (
   is => 'ro',
   init_arg => undef,
   lazy => 1,
   builder => '_build_scraped_content',
);

sub _build_scraped_content {
   my $s = $_[0]->_scrape( $_[0]->_index_content );
   $s->{data} = [grep %$_, @{$s->{data}}];
   $s
}

has _user_agent => (
   is => 'ro',
   lazy => 1,
   init_arg => 'user_agent',
   builder => '_build_user_agent',
   handles => { _get => 'get' },
);

sub _build_user_agent { require LWP::UserAgent; LWP::UserAgent->new }

has _members => (
   is => 'ro',
   # TODO: support passing memebers as either objects or strings that coerce
   init_arg => undef,
   lazy => 1,
   builder => '_build_members',
);

sub _build_members {
   require Apache::BalancerManager::Member;

   [
      map {;
         $_->{status} = $_->{status} =~ m/Ok/;
         $_->{manager} = $_[0];
         Apache::BalancerManager::Member->new($_),
      } @{$_[0]->_scraped_content->{data}}
   ]
}

sub get_member_by_index { $_[0]->_members->[$_[1]]; }

sub get_member_by_location {
   my ($self, $location) = @_;

   List::Util::first { $_->location eq $location } @{$self->_members};
}

sub member_count { scalar @{$_[0]->_members} }

1;

=pod

=head1 SYNOPSIS

  my $mgr = Apache::BalancerManager->new(
     url => 'http://127.0.0.1/balancer-manager',
  );
  my @services = (1..8);
 for my $backend (@services) {
    my $m = $mgr->get_member_by_location(
      sprintf 'http://127.0.0.1:50%02i', $_
    );
    $m->disable;
    $m->update;

    system('service', "backend_web_$_", 'restart');

    $m->enable;
    $m->update;
 }

=method new

=method get_member_by_location

 my $m = $bm->get_member_by_location('http://127.0.0.1:5001')

returns the L<Apache::BalancerManager::Member> with the passed location

=method get_member_by_index

 my $m = $bm->get_member_by_location(0)

returns the L<Apache::BalancerManager::Member> with the passed index

=method member_count

returns the number of L<Apache::BalancerManager::Member>'s that the load
balancer contains

=attr url

The url that the balance manager is running under.

=attr name

The name of the balancer.

=attr nonce

The nonce of the connection (autodetected.)

=attr user_agent

The user_agent
