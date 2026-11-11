// Plain Dart with no imports, so the build can run these graphs through real
// ffmpeg and measure them (tool/check_vocal_cut.dart).

/// Pro's Vocal cut, as an ffmpeg filter graph.
///
/// ffmpeg's `surround` filter looks at every frequency, many times a second,
/// and works out where it sits between the speakers. What sits in the middle
/// (usually the lead vocal) goes to a centre channel, and that channel is
/// left out. Everything else keeps its place: instruments panned left or
/// right, the stereo spread and the reverb (the back channels, folded into
/// the front), and the bass and kick drum (taken off the centre first, as
/// the LFE channel, and put back in). Unlike simply taking one side from the
/// other, the rest of the mix stays full.
///
/// It is still a filter, not a separation: an instrument sitting in the
/// middle with the vocal comes down with it, and the vocal's reverb can stay.
///
/// fl_x / fr_x narrow the front speakers, so a sound in the middle goes to the
/// centre channel only (by default the fronts get 70% of it too), while a
/// sound panned well over to one side stays where it was.
const vocalCutGraph = 'aformat=channel_layouts=stereo,'
    'surround=chl_out=5.1:lfe=1:lfe_mode=sub:lfe_low=120:lfe_high=250:fl_x=3:fr_x=3:bl_x=3:br_x=3,'
    'pan=stereo|c0=FL+0.7071*BL+LFE|c1=FR+0.7071*BR+LFE';
