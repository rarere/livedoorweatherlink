use v5.14;
use warnings;
use utf8;
use XML::Feed;
use LWP::UserAgent;
use JSON::PP;
use Encode;
use Data::Dumper;

my $uri = "http://weather.livedoor.com/forecast/rss/primary_area.xml";
my $ua = LWP::UserAgent->new();
my $response = $ua->get($uri);

my $xml;
if ($response->is_success) {
    $xml = $response->decoded_content;
} else {
    die $response->status_line;
}

my @lines = split('\n', $xml);
for my $line (@lines) {
    if ($line =~ m|<city title="(.*)" id="(\d+)" source=.*/>|) {
        jsonlink($2);
    }
}


sub jsonlink {
    my ($id) = @_;
    my $link;

    my $jsonuri = "http://weather.livedoor.com/forecast/webservice/json/v1?city=" . $id;
    my $response = $ua->get($jsonuri);

    my $rawjson;
    if ($response->is_success) {
        $rawjson = $response->decoded_content;
    } else {
        die $response->status_line;
    }
    my $json = decode_json($rawjson);
    say encode_utf8($json->{title}) . "," . $json->{link};

    for my $data (@{$json->{pinpointLocations}}) {
        say encode_utf8($data->{name}) . "," . $data->{link};
    }
}


1;
