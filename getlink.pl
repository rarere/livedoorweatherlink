#!/usr/bin/perl -w
use v5.14;
use warnings;
use utf8;
use XML::Feed;
use LWP::UserAgent;
use JSON::PP;
use Encode;
use Fcntl;
use DBI;
use Lingua::JA::Moji 'kana2romaji';
use Data::Dumper;

my $database = "./tenkilink.db";
my $sql_link;
my $sth_link;
my $sql_name;
my $sth_name;
my $link_id = 0;

my $name_hash = {};

&createtable;

my $dbh = DBI->connect("dbi:SQLite:dbname=$database", undef, undef, {
        AutoCommit => 0,
        RaiseError => 1,
        PrintError => 0,
    });


$sql_link = "insert into t_link (id, link, tenki_flag) values (?, ?, ?)";
$sth_link = $dbh->prepare($sql_link);
$sql_name = "insert into t_name (name, link_id) values (?, ?)";
$sth_name = $dbh->prepare($sql_name);



my $uri = "http://yanok.net/dist/romaji-chimei-csv/romaji-chimei-all-u.csv";
my $ua = LWP::UserAgent->new();
my $response = $ua->get($uri);
my $timeicsv;
if ($response->is_success) {
    $timeicsv = $response->decoded_content;
} else {
    die $response->status_line;
}

$uri = "http://weather.livedoor.com/forecast/rss/primary_area.xml";
$response = $ua->get($uri);
my $xml;
if ($response->is_success) {
    $xml = $response->decoded_content;
} else {
    die $response->status_line;
}

my @timei_lines = split("\n", $timeicsv);


my @xml_lines = split('\n', $xml);
for my $line (@xml_lines) {
    if ($line =~ m|<city title="(.*)" id="(\d+)" source=.*/>|) {
        jsonlink($2);
    }
}
$dbh->commit;

while (my ($key, $value) = each %$name_hash) {
    $sth_name->execute(encode_utf8($key), $value);
}
$dbh->commit;
$dbh->disconnect;



###################################
sub createtable {
    if ( -f $database) {
        unlink $database or die "$!: $database";
    }
    my $dbh = DBI->connect("dbi:SQLite:dbname=$database", undef, undef, {
            AutoCommit => 1,
            RaiseError => 1,
            PrintError => 1,
        });
    my $create_table = <<'EOS';
CREATE TABLE t_link(
    id integer primary key,
    link text,
    tenki_flag int default 0
);
EOS
    $dbh->do($create_table);
    $create_table = <<'EOS';
CREATE TABLE t_name(
    id integer primary key autoincrement,
    name text not null,
    link_id int not null,
    foreign key(link_id) references t_link(id)
);
EOS
    $dbh->do($create_table);
    $dbh->disconnect();
}

###################################
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
    sleep 1;

    my $json = decode_json($rawjson);
    say encode_utf8($json->{title});
    $link_id++;
    $sth_link->execute($link_id, $json->{link}, 1);
    $name_hash->{$json->{title}} = $link_id;

    for my $data (@{$json->{pinpointLocations}}) {
        $link_id++;
        $sth_link->execute($link_id, $data->{link}, 0);
        $name_hash->{$data->{name}} = $link_id;

        for my $kana_line (@timei_lines) {
            my @kana = split(",", $kana_line);
            if ($data->{name} eq $kana[0]) {
                $name_hash->{$kana[1]} = $link_id;
                $name_hash->{$kana[2]} = $link_id;

                my @romaji;
                push(@romaji, kana2romaji($kana[1], {style=>"passport"}));
                push(@romaji, kana2romaji($kana[1], {style=>"kunrei",
                        ve_type=>"none"}));
                push(@romaji, kana2romaji($kana[1], {style=>"kunrei",
                        ve_type=>"wapuro"}));
                push(@romaji, kana2romaji($kana[1], {wapuro=>1}));

                for my $roma (@romaji) {
                    $name_hash->{$roma} = $link_id;
                }
            }
        }
    }
}

