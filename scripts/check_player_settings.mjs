const fs=await import('node:fs/promises');const vm=await import('node:vm');
const html=await fs.readFile(new URL('../youtube-player.html',import.meta.url),'utf8');
const code=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const calls=[],states=[];let events,tick;const player={getPlaybackRate:()=>player.rate,getPlayerState:()=>1,getCurrentTime:()=>player.time,getVolume:()=>70,isMuted:()=>false,getOption:()=>2,setVolume(v){calls.push(['volume',v])},unMute(){},mute(){},setOption(m,k,v){calls.push(['caption',v])},rate:1,time:0,setPlaybackRate(rate){this.rate=rate;calls.push(['rate',rate]);},seekTo(t){this.time=t;calls.push(['seek',t]);},playVideo(){calls.push(['play']);},pauseVideo(){calls.push(['pause']);},loadVideoById(o){calls.push(['load',o.startSeconds]);},cueVideoById(o){calls.push(['cue',o.startSeconds]);}};
const window={addEventListener(){},parent:{postMessage(){}},webkit:{messageHandlers:{youtubeState:{postMessage:p=>states.push(p)}}}};
const document={querySelector:()=>null,baseURI:'https://app.example/',createElement:()=>({}),head:{append(){}},addEventListener(){}};
let now=0;const context={Date:{now:()=>now},window,document,location:{origin:'https://app.example'},URL,Number,setTimeout(){},setInterval(fn){tick=fn;return 1},clearInterval(){},YT:{PlayerState:{PLAYING:1},Player:function(id,options){events=options.events;return player;}}};vm.runInNewContext(code,context);const api=window.WordAheadYouTube;
api.load({action:'seek',videoId:'M7lc1UVf-VE',start:297,play:true,rate:1});window.onYouTubeIframeAPIReady();events.onReady();
api.load({action:'seek',videoId:'M7lc1UVf-VE',start:304,play:true,rate:1});
const moves=calls.filter(c=>['load','cue','seek','play'].includes(c[0])).length;
for(let i=0;i<10;i++)api.setRate(.75);
if(calls.filter(c=>['load','cue','seek','play'].includes(c[0])).length!==moves)throw Error('Rate changed playback position');
api.load({action:'pause'});api.setRate(1.25);
if(calls.filter(c=>['load','cue','seek','play'].includes(c[0])).length!==moves)throw Error('Pause/rate restarted playback');
api.load({action:'rate',rate:1.5});if(player.rate!==1.5)throw Error('Rate command ignored');
now=6000;events.onPlaybackRateChange({data:.75});if(states.at(-1).rate!==.75)throw Error('YouTube speed not published');
console.log('PASS: repeated rate restoration never seeks or starts playback; pause stays paused; rate-only command and YouTube speed changes work');

api.suspend();player.rate=1;events.onPlaybackRateChange({data:1});
api.restoreSettings({rate:.75,captionFontSize:2,volume:70,muted:false});
if(player.rate!==.75)throw Error('Saved rate not restored');
player.rate=1;events.onStateChange({data:1});tick();
if(states.at(-1).rate!==.75)throw Error('Transient reset overwrote saved rate');
if(!calls.some(c=>c[0]==='caption'&&c[1]===2))throw Error('Caption size not restored');
if(calls.filter(c=>['load','cue','seek','play'].includes(c[0])).length!==moves)throw Error('Resume restored position instead of settings');
console.log('PASS: background reset ignored; rate and supported caption settings restored without seeking');

api.suspend();const n=states.length;events.onStateChange({data:1});tick();if(states.length<=n)throw Error('Manual playback after suspend failed to resume caption timing');console.log('PASS: time updates resume after navigation or speech pause');

api.restoreSettings({rate:.7});events.onPlaybackRateChange({data:.7});player.rate=1;events.onPlaybackRateChange({data:1});tick();if(player.rate!==.7||states.at(-1).rate!==.7)throw Error("Late foreground reset erased custom speed");
now+=6000;player.rate=1.25;events.onPlaybackRateChange({data:1.25});tick();if(states.at(-1).rate!==1.25)throw Error("User speed change ignored after resume");
console.log("PASS: delayed foreground reset preserves custom speed; subsequent user changes work");
