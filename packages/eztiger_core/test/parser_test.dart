import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

void expectParse(String name,
    {required String title, String? artist, String? version, String? code, String? folder}) {
  final r = parseFileName(name, folderName: folder);
  expect(r.title, title, reason: 'title of "$name" ($r)');
  expect(r.artist, artist, reason: 'artist of "$name" ($r)');
  if (version != null) expect(r.version, version, reason: 'version of "$name"');
  if (code != null) expect(r.catalogueCode, code, reason: 'code of "$name"');
}

void main() {
  group('catalogue codes', () {
    test('code, title, artist (left for the scanner to order)', () {
      final r = parseFileName('ZM6S01-02 - Bad Moon Rising - Creedence Clearwater Revival');
      expect(r.catalogueCode, 'ZM6S01-02');
      expect({r.title, r.artist}, {'Bad Moon Rising', 'Creedence Clearwater Revival'});
      expect(r.orderKnown, isFalse);
    });
    test('Surname, The marks the artist', () {
      expectParse('SC8125-04 - Eagles, The - Desperado',
          title: 'Desperado', artist: 'The Eagles', code: 'SC8125-04');
    });
    test('no spaces around hyphens', () {
      expectParse('SF126-06-BEAUTIFUL SOUTH-PERFECT 10',
          title: 'Perfect 10', artist: 'Beautiful South', code: 'SF126-06');
      expectParse('PX-006-07-Billie Jo Spears-57 Chevrolet',
          title: '57 Chevrolet', artist: 'Billie Jo Spears');
    });
    test('other code shapes', () {
      for (final code in [
        'STTW1263-4-03',
        'ZOOMPA063-08',
        'MMVE3-01-06',
        'EZA08-07',
        'KV-27296',
        'ZKL002-19',
        'SFMW921-14',
        'ZMG77 15'
      ]) {
        expect(parseFileName('$code - Delilah - Tom Jones').catalogueCode, code, reason: code);
      }
    });
    test('a code is only stripped if a separator survives it', () {
      expectParse('Blink 182 - All The Small Things', title: 'All The Small Things', artist: 'Blink 182');
      expectParse('UB40 - Red Red Wine', title: 'Red Red Wine', artist: 'UB40');
      expectParse('AC-DC - Highway To Hell', title: 'Highway To Hell', artist: 'AC-DC');
      expectParse('Jay-Z - Empire State Of Mind', title: 'Empire State Of Mind', artist: 'Jay-Z');
      expectParse('10cc - Dreadlock Holiday', title: 'Dreadlock Holiday', artist: '10cc');
    });
    test('code then brand', () {
      final r = parseFileName('ZM80003 - Acoustative - Fly Me To The Moon - Frank Sinatra');
      expect(r.catalogueCode, 'ZM80003');
      expect(r.brand, 'Acoustative');
      expect({r.title, r.artist}, {'Fly Me To The Moon', 'Frank Sinatra'});
    });
  });

  group('brands', () {
    test('Zoom Karaoke is Title - Artist', () {
      expectParse('Zoom Karaoke - My Way - Frank Sinatra', title: 'My Way', artist: 'Frank Sinatra');
    });
    test('Acoustative with the artist in a trailing bracket', () {
      expectParse('Acoustative - Human (Two Semitones Down) (Killers)',
          title: 'Human', artist: 'Killers', version: 'Two Semitones Down');
    });
  });

  group('noise', () {
    test('trailing numeric ids', () {
      expectParse('John Legend - All Of Me (Tiesto Remix) - 46830',
          title: 'All Of Me', artist: 'John Legend', version: 'Tiesto Remix');
      expectParse('Amy Winehouse – Back To Black – 59923', title: 'Back To Black', artist: 'Amy Winehouse');
    });
    test('leading track numbers, but not 9 to 5 or 10cc', () {
      expect(parseFileName('02 Thats Amore - Dean Martin').title, anyOf('Thats Amore', 'Dean Martin'));
      expectParse('9.01 My Kind Of Town', title: 'My Kind Of Town');
      expectParse('1.The Lady Is A Tramp', title: 'The Lady Is A Tramp');
      expectParse('09  DEAN MARTIN - SWAY', title: 'Sway', artist: 'Dean Martin');
      expect({parseFileName('9 to 5 - Dolly Parton').title, parseFileName('9 to 5 - Dolly Parton').artist},
          contains('9 to 5'));
    });
    test('underscores', () {
      expectParse('dean_martin_-_on_an_evening_in_roma',
          title: 'On an Evening in Roma', artist: 'Dean Martin');
      expectParse('Electric_Light_Orchestra_Telephone_Line(Custom_Backing_Track-2)',
          title: 'Electric Light Orchestra Telephone Line');
    });
    test('YouTube-style noise, and the artist rescued from "Originally Performed By"', () {
      expectParse('Sweet Caroline (Karaoke Version) (Originally Performed By Neil Diamond) - YouTube',
          title: 'Sweet Caroline', artist: 'Neil Diamond');
      expectParse('Shallow [BEST VERSION] (480p) 🎤', title: 'Shallow');
      final r = parseFileName("Don’t Stop Believin’ — Journey");
      expect({r.title, r.artist}, {"Don't Stop Believin'", 'Journey'});
    });
    test('runs of spaces where | was stripped', () {
      expectParse('Mr Brightside   The Killers', title: 'The Killers', artist: 'Mr Brightside');
    });
  });

  group("Dean's version notes are kept", () {
    test('unbracketed', () {
      expectParse('minnie the moocher down 2', title: 'Minnie the Moocher', version: 'down 2');
      expectParse('my way in G', title: 'My Way', version: 'in G');
      expectParse('Somethin Stupid with bv', title: 'Somethin Stupid', version: 'with bv');
      expectParse('Mustang Sally_no_vocals_split_by_lalalai',
          title: 'Mustang Sally', version: 'no vocals split by lalalai');
      expectParse('sway extended', title: 'Sway', version: 'extended');
      expectParse('Delilah - Tom Jones clean ending',
          title: 'Tom Jones', artist: 'Delilah', version: 'clean ending');
    });
    test('bracketed', () {
      expectParse('Acoustative - (Let Me Be Your) Teddy Bear (Original Male Key)',
          title: '(Let Me Be Your) Teddy Bear', version: 'Original Male Key');
      expectParse('Hall And Oates - You Make My Dreams (Key of D)',
          title: 'You Make My Dreams', artist: 'Hall And Oates', version: 'Key of D');
    });
    test('a note never eats the whole name', () {
      expectParse('Slow', title: 'Slow');
      expectParse('live', title: 'Live');
    });
  });

  group('artists', () {
    test('Surname, First is flipped', () {
      expectParse('Jones, Tom - Delilah', title: 'Delilah', artist: 'Tom Jones');
      expectParse('Righteous Brothers, The - Unchained Melody',
          title: 'Unchained Melody', artist: 'The Righteous Brothers');
    });
    test('meaningless names take the artist from the folder', () {
      expectParse('02', title: 'Track 02', artist: 'Brenda Lee', folder: 'Brenda Lee');
      expectParse('01 Track', title: 'Track 01', artist: 'dean cd', folder: 'dean cd');
    });
    test('folder name decides the order', () {
      expectParse('Sway - Dean Martin', title: 'Sway', artist: 'Dean Martin', folder: 'Dean Martin');
    });
    test('title-only lowercase files', () {
      expectParse('sweet caroline', title: 'Sweet Caroline');
      expectParse('hurt', title: 'Hurt');
    });
  });

  group('real names from the library', () {
    test('track numbers glued on with a hyphen', () {
      expectParse("22-You've Been Gone Too Long - Ann Sexton",
          title: 'Ann Sexton', artist: "You've Been Gone Too Long");
      final r = parseFileName("11-CYNTHIA SHEELER _ I'LL CRY OVER YOU");
      expect({r.title, r.artist}, {"I'll Cry Over You", 'Cynthia Sheeler'});
    });
    test('CamelCase names with a key on the end', () {
      expectParse('SummerOf69BryanAdamsD', title: 'Summer Of 69 Bryan Adams', version: 'in D');
      expectParse('ChasingPavementsAdeleCm', title: 'Chasing Pavements Adele', version: 'in Cm');
    });
    test('downloaded MP3+G zips', () {
      expectParse('Michael_Buble_When_You_re_Smiling_(Buble_NBC_Special)(MP3+CDG_Karaoke)_10303492',
          title: "Michael Buble When You're Smiling (Buble NBC Special)");
      expectParse('Frank_Sinatra_Bad_Bad_Leroy_Brown(MP3+CDG_Karaoke)_38412',
          title: 'Frank Sinatra Bad Bad Leroy Brown');
    });
    test('YouTube covers with a style description', () {
      expectParse('Every Breath You Take - The Police   Blues Rock Version',
          title: 'The Police', artist: 'Every Breath You Take', version: 'Blues Rock Version');
      expectParse('I Don\'t Want To Talk About It - Symphonic Jazz Blues Fusion Cover',
          title: "I Don't Want To Talk About It", version: 'Symphonic Jazz Blues Fusion Cover');
    });
    test('durations and covers', () {
      expectParse('COMFORTABLY NUMB (6.10)', title: 'Comfortably Numb');
      expectParse("Eminem - Without Me (1950's Motown Soul AI Cover) [BEST VERSION]",
          title: 'Without Me', artist: 'Eminem', version: "1950's Motown Soul AI Cover");
      expectParse('Rick Astley - Cry For Help - Karaoke Version from Zoom Karaoke',
          title: 'Cry For Help', artist: 'Rick Astley');
    });
    test('one-word surname, long first part', () {
      expectParse('ZM6S03-17 - Young Girl - Puckett, Gary And The Union Gap',
          title: 'Young Girl', artist: 'Puckett, Gary And The Union Gap');
    });
  });
}
