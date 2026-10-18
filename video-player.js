const WordAheadVideo = {
  videoId:null,frame:null,pending:null,playbackRate:Number(localStorage.getItem('wa-youtube-playback-rate'))||1,
  valid(id){return /^[A-Za-z0-9_-]{11}$/.test(id||'');},
  rate(value){const allowed=[.25,.5,.75,1,1.25,1.5,1.75,2];const n=Number(value);return allowed.includes(n)?n:1;},
  native(){return window.webkit?.messageHandlers?.youtubePlayer;},
  show(video){
    if(!this.valid(video?.youtubeId)){this.hide();return;}
    const changed=this.videoId!==video.youtubeId;
    this.videoId=video.youtubeId;
    if(this.native()){this.native().postMessage({action:'show',videoId:this.videoId,rate:this.playbackRate});return;}
    const host=document.querySelector('#youtube-player-host');host.hidden=false;
    if(!this.frame){
      this.frame=document.createElement('iframe');this.frame.title='YouTube 영상 플레이어';
      this.frame.allow='autoplay; encrypted-media; fullscreen; picture-in-picture';this.frame.allowFullscreen=true;
      this.frame.onload=()=>{if(this.pending)this.send(this.pending);};
      this.frame.src='youtube-player.html';host.append(this.frame);
    }
    if(changed||this.pending?.action==='pause')this.send({action:'load',videoId:this.videoId,start:0,play:false,rate:this.playbackRate});
  },
  send(command){
    this.pending=command;
    if(this.native()){this.native().postMessage(command);return;}
    this.frame?.contentWindow?.postMessage({type:'wordahead-player',...command},location.origin);
  },
  seek(video,start){
    if(!this.valid(video?.youtubeId)||typeof start!=='number'||!Number.isFinite(start)||start<0)return;
    this.show(video);this.send({action:'seek',videoId:video.youtubeId,start,play:true,rate:this.playbackRate});
    document.querySelector('#youtube-player-host')?.scrollIntoView({block:'nearest',behavior:'smooth'});
  },
  setRate(value){this.playbackRate=this.rate(value);localStorage.setItem('wa-youtube-playback-rate',String(this.playbackRate));this.send({action:'rate',rate:this.playbackRate});},
  applyRate(){this.send({action:'rate',rate:this.playbackRate});},
  pause(){this.send({action:'pause',rate:this.playbackRate});},
  hide(){
    this.pause();if(this.native())this.native().postMessage({action:'hide'});
    const host=document.querySelector('#youtube-player-host');if(host)host.hidden=true;
  }
};
window.addEventListener('message',event=>{
  if(event.origin!==location.origin||event.data?.type!=='wordahead-player-time'||event.source!==WordAheadVideo.frame?.contentWindow)return;
  if(Number.isFinite(event.data.rate)){WordAheadVideo.playbackRate=WordAheadVideo.rate(event.data.rate);localStorage.setItem('wa-youtube-playback-rate',String(WordAheadVideo.playbackRate));window.dispatchEvent(new CustomEvent('wordahead:playbackrate',{detail:{rate:WordAheadVideo.playbackRate}}));}
  window.dispatchEvent(new CustomEvent('wordahead:playbacktime',{detail:{time:event.data.time}}));
});
document.addEventListener('visibilitychange',()=>{if(document.hidden)WordAheadVideo.pause();});
window.addEventListener('pagehide',()=>WordAheadVideo.pause());
