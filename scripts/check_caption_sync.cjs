const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('app.js','utf8');
const context={Intl};vm.createContext(context);
vm.runInContext(source.slice(source.indexOf('function cleanCaptionText'),source.indexOf('function openReader')),context);
const cues=context.captionSentences({segments:[{start:'10',text:'Later.'},{start:2,text:'First.'},{start:2,text:'Second.'},{start:'invalid',text:'Bad.'}]});
assert.equal(cues.length,2);assert.equal(cues[0].start,2);assert.equal(cues[0].text,'First. Second.');assert.equal(cues[1].start,10);
const makeLine=start=>{const values=new Set();return{dataset:{cueStart:String(start)},getBoundingClientRect:()=>({top:200}),classList:{contains:c=>values.has(c),remove:c=>values.delete(c),toggle(c,on){on?values.add(c):values.delete(c)}}};};
let lines=[makeLine(2),makeLine(10)];
const playbackContext={window:{addEventListener(){},scrollTo(){},scrollY:0},activeVideo:{youtubeId:'current'},Number,Math,getComputedStyle:()=>({lineHeight:'32px'}),$:s=>s==='#reader-view'?{hidden:false}:{getBoundingClientRect:()=>({bottom:60})},$$:()=>lines};
vm.createContext(playbackContext);vm.runInContext(source.slice(source.indexOf('window.WordAheadPlayback='),source.indexOf("window.addEventListener('wordahead:playbackrate'")),playbackContext);
const player=playbackContext.window.WordAheadPlayback;
player.update(11,'current');assert(lines[1].classList.contains('audio-active'));
lines=[makeLine(2),makeLine(10)];player.update(11,'current');assert(lines[1].classList.contains('audio-active'));
player.update(3,'stale-video');assert(lines[1].classList.contains('audio-active'));
player.update(3,'current');assert(lines[0].classList.contains('audio-active'));assert(!lines[1].classList.contains('audio-active'));
console.log('PASS: cue ordering/merging, highlight after rerender, stale video ignored, backwards seek');

const fragments=[{start:0,text:'I understand'},{start:1,text:'that learning a language'},{start:2,text:'takes time.'},{start:3,text:'This is'},{start:4,text:'another complete sentence.'}];
const grouped=context.captionSentences({segments:fragments});assert.equal(grouped.length,2);assert.equal(grouped[0].start,0);assert.equal(grouped[1].start,3);assert.equal(grouped[0].text,'I understand that learning a language takes time.');
const unpunctuated=Array.from({length:20},(_,i)=>({start:i,text:'a short subtitle fragment'}));const blocks=context.captionSentences({segments:unpunctuated});assert(blocks.length<unpunctuated.length);assert(blocks.every(b=>b.text.length>=90));assert.equal(blocks.map(x=>x.text).join(' '),unpunctuated.map(x=>x.text).join(' '));
const title=context.captionSentences({segments:[{start:0,text:'Dr.'},{start:1,text:'Smith is speaking.'}]});assert.equal(title.length,1);
console.log('PASS: fragments group into sentences or larger blocks without text loss or invented timestamps');

const turns=context.captionSentences({segments:[{start:0,text:'A short question',speaker:'host'},{start:2,text:'a short answer',speaker:'guest'}]});assert.equal(turns.length,2);assert.equal(turns[1].start,2);
const markers=context.captionSentences({segments:[{start:0,text:'Question fragment'},{start:2,text:'>> Answer fragment'},{start:4,text:'continues'}]});assert.equal(markers.length,2);assert.equal(markers[1].start,2);assert(!markers[1].text.includes('>>'));
const internal=context.captionTurnSegments([{start:10,duration:8,parts:[{start:10,text:'A question '},{start:13,text:'>> An answer'}]}]);assert.equal(internal.length,2);assert.equal(internal[1].start,13);assert(internal[1].turnStart);assert.equal(internal[1].end,18);
const persisted=context.captionTurnSegments(internal);assert.equal(persisted[1].end,18);assert(persisted[1].turnStart);
const long=context.captionSentences({segments:[{start:0,duration:60,speaker:'host',text:'a long speech '.repeat(100)}]},text=>text.length<=120);assert(long.length>1);assert(long.every(x=>x.text.length<=120));assert(long[1].start>0);assert(long[1].estimated);assert.equal(long.map(x=>x.text).join(' '),'a long speech '.repeat(100).trim());
console.log('PASS: speaker boundaries, in-cue turn timestamps, persisted timing, six-line split without text loss');
