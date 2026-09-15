// Capture diagnostics and pause-aware review. Cached review never authorizes a stale write.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
namespace WD1Kit.Native {
 public class CapturedValue {public double Value;public double? Capacity;public int Generation;public DateTime At;public string Error;}
 public class CapturePreview {
  public string OptionId,Site,Code,Explanation;public bool Installed,HookIntact,BufferReadable,Coherent,PointerObserved,PointerValid,HasHit,Fresh;
  public int StableSamples,PointerAlignment,Generation,PointerChanges,ReadFailures;public long HitCount;public double? SecondsSinceHit,Value,ValueAgeSeconds;public bool CachedOnly;
 }
 public class PendingOnce {public string Id,Scope;public long Pointer,Sequence;public int Generation;public double Delta;public DateTime Expires;}
 public sealed partial class Engine {
  const double FreshSeconds=2,ReviewArmSeconds=120;const int QueueSeconds=30;
  readonly Dictionary<string,PendingOnce> pending=new Dictionary<string,PendingOnce>();
  readonly Dictionary<string,CapturedValue> cached=new Dictionary<string,CapturedValue>();
  public bool HasPending {get{return pending.Count>0;}}
  static bool ValidPointer(long p){return p>=0x10000&&p<0x00007fffffffffff&&(p&7)==0;}
  double? HitAge(Capture c){if(c.Seen==DateTime.MinValue)return null;double age=(clock()-c.Seen).TotalSeconds;return age<0?(double?)null:age;}
  bool Fresh(Capture c){var age=HitAge(c);return c.HookIntact&&c.BufferReadable&&c.Coherent&&c.HasHit&&ValidPointer(c.Pointer)&&c.Stable>=3&&age.HasValue&&age.Value<=FreshSeconds;}
  string CaptureCode(Capture c){
   if(!Alive)return "GAME_EXITED";
   if(!c.HookIntact)return c.HookReadFailed?"HOOK_UNREADABLE":"HOOK_CHANGED";
   if(!c.BufferReadable)return "BUFFER_UNREADABLE";
   if(!c.Coherent)return "BUFFER_CHANGING";
   if(!c.HasHit)return c.Sequence==0?"HOOK_NOT_HIT":"WAIT_NEW_SCOPE_HIT";
   if(c.Pointer==0)return "HIT_WITH_NULL_POINTER";
   if(c.Pointer<0x10000||c.Pointer>=0x00007fffffffffff)return "POINTER_RANGE_REJECTED";
   if((c.Pointer&7)!=0)return "POINTER_ALIGNMENT_REJECTED";
   if(c.Stable<3)return "POINTER_NOT_STABLE";
   if(Fresh(c))return "READY_LIVE";
   var age=HitAge(c);return age.HasValue&&age.Value<=ReviewArmSeconds?"CACHED_PAUSED_OR_STALE":"CACHED_EXPIRED";
  }
  static string Explain(string code){switch(code){
   case "NOT_INSTALLED":return "尚未安装此项捕获。";
   case "CODE_ONLY":return "代码开关不需要资源对象捕获。";
   case "HOOK_NOT_HIT":return "捕获跳转已安装，但执行计数为0；不能用唯一签名命中代替入口被触发。";
   case "WAIT_NEW_SCOPE_HIT":return "活动范围已切换，等待该范围内的新一次捕获。";
   case "HOOK_CHANGED":return "目标跳转与本工具安装内容不同，停止并诊断，不自动覆盖。";
   case "HOOK_UNREADABLE":return "无法读取已安装跳转，不允许使用旧对象。";
   case "BUFFER_UNREADABLE":return "捕获缓冲区不可读。";
   case "BUFFER_CHANGING":return "读取期间捕获内容变化，本次样本不作为稳定证据。";
   case "HIT_WITH_NULL_POINTER":return "入口被执行，但当前对象为0。";
   case "POINTER_RANGE_REJECTED":return "入口被执行，但对象超出合法地址范围。";
   case "POINTER_ALIGNMENT_REJECTED":return "对象未通过当前8字节对齐约束；不猜测改地址。";
   case "POINTER_NOT_STABLE":return "已见对象，尚未连续通过3次稳定采样。";
   case "READY_LIVE":return "当前有新鲜、稳定样本；这仍不证明对象身份/游戏效果。";
   case "CACHED_PAUSED_OR_STALE":return "曾成功捕获，超过2秒没有新心跳。仅显示缓存；切窗暂停可能导致此状态，不需要抢在2秒内操作。";
   case "CACHED_EXPIRED":return "仅保留历史缓存用于诊断，超过120秒不得据此排队或预置写入。";
   case "FIELD_UNREADABLE":return "对象被捕获，但该资源字段不可读。";
   case "FIELD_OUT_OF_RANGE":return "资源原始值不在已定义范围，不能作为正确对象。";
   case "GAME_EXITED":return "游戏会话已结束。";
   default:return "等待捕获诊断。";
  }}
  void CancelSite(string site,string reason){
   foreach(var id in active.Where(a=>a.Value.Option.Site==site).Select(a=>a.Key).ToArray()){active.Remove(id);Messages[id]=reason;}
   foreach(var id in pending.Where(a=>Find(a.Key).Site==site).Select(a=>a.Key).ToArray()){pending.Remove(id);Messages[id]=reason;}
  }
  void ClearSiteCache(string site){foreach(var id in cached.Keys.Where(k=>Find(k).Site==site).ToArray())cached.Remove(id);}
  void Sample(){foreach(var c in captures.Values){
   try{
    c.HookIntact=memory.Read(c.Site.Address,c.Site.Definition.Expected.Length).SequenceEqual(Contracts.Jump(c.Site.Address,c.Page,c.Site.Definition.Expected.Length));c.HookReadFailed=false;
   }catch{c.HookIntact=false;c.HookReadFailed=true;}
   if(!c.HookIntact){c.Stable=0;CancelSite(c.Site.Definition.Id,"捕获代码变化/不可读，取消所有相关写入与排队");continue;}
   try{
    var a=memory.Read(c.Page+0x800,16);var b=memory.Read(c.Page+0x800,16);c.BufferReadable=true;
    long p=BitConverter.ToInt64(b,0),seq=BitConverter.ToInt64(b,8);c.Coherent=a.SequenceEqual(b);
    if(!c.Coherent){c.Stable=0;continue;}
    bool changed=p!=c.Pointer;
    if(changed){CancelSite(c.Site.Definition.Id,"对象变化，已停止并取消排队；不自动写入新对象");ClearSiteCache(c.Site.Definition.Id);c.Pointer=p;c.Stable=0;c.HasHit=false;c.Seen=DateTime.MinValue;c.Generation++;c.PointerChanges++;}
    if(seq!=c.Sequence){c.Sequence=seq;c.Seen=clock();c.HasHit=true;}
    if(ValidPointer(p)){c.Stable=Math.Min(c.Stable+1,1000000);}else c.Stable=0;
   }catch{c.BufferReadable=false;c.Coherent=false;c.Stable=0;c.ReadFailures++;continue;}
   if(Fresh(c))foreach(var o in Contracts.Options.Where(o=>o.Site==c.Site.Definition.Id&&!o.Kind.Contains("patch")&&o.Kind!="return_zero")){
    var v=new CapturedValue{Generation=c.Generation,At=clock()};
    try{v.Value=ReadValue(o,c.Pointer);if(o.Kind=="capacity_f32")v.Capacity=Capacity(o,c.Pointer);}catch(IOException ex){v.Error=ex.Message.IndexOf("范围",StringComparison.Ordinal)>=0||ex.Message.IndexOf("容量",StringComparison.Ordinal)>=0?"FIELD_OUT_OF_RANGE":"FIELD_UNREADABLE";}catch{v.Error="FIELD_UNREADABLE";}
    cached[o.Id]=v;
   }
  }}
  public CapturePreview Preview(string id){
   var o=Find(id);var r=new CapturePreview{OptionId=id,Site=o.Site,Code="NOT_INSTALLED"};
   if(o.Kind.Contains("patch")||o.Kind=="return_zero"){r.Code="CODE_ONLY";r.Explanation=Explain(r.Code);return r;}
   Capture c;if(!captures.TryGetValue(o.Site,out c)){r.Explanation=Explain(r.Code);return r;}
   r.Installed=true;r.Code=CaptureCode(c);r.HookIntact=c.HookIntact;r.BufferReadable=c.BufferReadable;r.Coherent=c.Coherent;r.PointerObserved=c.Pointer!=0;r.PointerValid=ValidPointer(c.Pointer);r.PointerAlignment=(int)(c.Pointer&7);r.HasHit=c.HasHit;r.HitCount=c.Sequence;r.StableSamples=c.Stable;r.Generation=c.Generation;r.PointerChanges=c.PointerChanges;r.ReadFailures=c.ReadFailures;r.SecondsSinceHit=HitAge(c);r.Fresh=Fresh(c);
   CapturedValue v;if(cached.TryGetValue(id,out v)&&v.Generation==c.Generation){if(v.Error==null){r.Value=v.Value;r.ValueAgeSeconds=Math.Max(0,(clock()-v.At).TotalSeconds);r.CachedOnly=!r.Fresh;}else if(r.Code=="READY_LIVE"||r.Code=="CACHED_PAUSED_OR_STALE"||r.Code=="CACHED_EXPIRED")r.Code=v.Error;}
   r.Explanation=Explain(r.Code);return r;
  }
  public string CaptureSummary(string id){var p=Preview(id);return "["+p.Code+"] 次数="+p.HitCount+" / 稳定="+p.StableSamples+(p.SecondsSinceHit.HasValue?" / 距刷新="+p.SecondsSinceHit.Value.ToString("0.0")+"s":"")+(p.Value.HasValue?" / "+(p.CachedOnly?"缓存":"样本")+"="+p.Value.Value.ToString("0.###"):"");}
  public bool HasCaptureFor(string id){return captures.ContainsKey(Find(id).Site);}
  Capture GetCapture(Option o){Capture c;if(!captures.TryGetValue(o.Site,out c)||!Fresh(c)){var p=Preview(o.Id);throw new IOException("["+p.Code+"] "+p.Explanation);}return c;}
  Capture ReviewCapture(Option o){
   var p=Preview(o.Id);if(p.Code!="READY_LIVE"&&p.Code!="CACHED_PAUSED_OR_STALE")throw new IOException("["+p.Code+"] "+p.Explanation);
   CapturedValue v;if(!cached.TryGetValue(o.Id,out v)||v.Error!=null)throw new IOException("没有当前对象的有效资源样本，不能预置写入。");return captures[o.Site];
  }
  public void QueueOnce(string id,double? custom=null){
   Permit();var o=Find(id);if(!(o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_"))||o.Scope!=Scope)throw new IOException("一次性操作 / 活动范围不符。");
   if(pending.Count>0)throw new IOException("已有一次性请求排队，请等完成或取消，不能重复累计提交。");
   if(active.Values.Any(a=>a.Option.Site==o.Site&&a.Option.Offset==o.Offset))throw new IOException("先关闭同字段无限/锁定开关，再排队独立增减。");
   var c=ReviewCapture(o);double delta=custom??o.Value;
   if(double.IsNaN(delta)||double.IsInfinity(delta)||delta!=Math.Floor(delta)||Math.Abs(delta)>1000000)throw new IOException("增减量无效。");
   pending[id]=new PendingOnce{Id=id,Scope=Scope,Pointer=c.Pointer,Generation=c.Generation,Sequence=c.Sequence,Delta=delta,Expires=clock().AddSeconds(QueueSeconds)};
   Messages[id]="已排队一次；尚未写入。等待同一对象的新心跳，30秒自动取消。";
  }
  public void CancelQueued(){foreach(var id in pending.Keys.ToArray())Messages[id]="已取消排队，未执行该请求";pending.Clear();}
  void ProcessQueued(){foreach(var q in pending.Values.ToArray()){
   if(!pending.ContainsKey(q.Id))continue;
   if(clock()>=q.Expires){pending.Remove(q.Id);Messages[q.Id]="排队超时，未执行；不会在迟到捕获时补写";continue;}
   var o=Find(q.Id);Capture c;
   if(!captures.TryGetValue(o.Site,out c)||q.Scope!=Scope||q.Generation!=c.Generation||q.Pointer!=c.Pointer){pending.Remove(q.Id);Messages[q.Id]="目标或范围改变，排队已取消";continue;}
   if(!Fresh(c)||c.Sequence==q.Sequence)continue;
   // Remove before writing: even an exception after WriteData must never retry the increment.
   pending.Remove(q.Id);try{Once(q.Id,q.Delta);}catch(Exception ex){Messages[q.Id]="一次性请求停止，不自动重试："+ex.Message;}
  }}
 }
}
