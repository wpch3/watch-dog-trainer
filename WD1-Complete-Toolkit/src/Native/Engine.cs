using System;
using System.Linq;
using System.Collections.Generic;
using System.IO;
namespace WD1Kit.Native {
 public class Resolution {public Site Definition;public int Hits;public long Address;public bool Exact;public string Status;}
 public class Capture {public Resolution Site;public long Page,Pointer,Sequence;public int Stable,Generation,PointerChanges,ReadFailures;public DateTime Seen;public int CodeLength;public bool HookIntact,HookReadFailed,BufferReadable,Coherent,HasHit;}
 public class LiveValue {public Option Option;public long Pointer,ArmSequence;public int Generation;public bool WaitNewHit;public double Target;public string State;}
 public sealed partial class Engine:IDisposable {
  readonly IMemory memory;readonly Func<bool> authorized;readonly Func<DateTime> clock;bool disposed;
  readonly Dictionary<string,Capture> captures=new Dictionary<string,Capture>();
  readonly Dictionary<string,List<Change>> patches=new Dictionary<string,List<Change>>();
  readonly Dictionary<string,LiveValue> active=new Dictionary<string,LiveValue>();
  public readonly Dictionary<string,Resolution> Sites=new Dictionary<string,Resolution>();
  public readonly Dictionary<string,string> Messages=new Dictionary<string,string>();
  public string Scope {get;private set;} public bool Alive {get{return !disposed&&memory.Alive;}}
  public bool HasCode {get{return captures.Count>0||patches.Count>0;}}
  public Engine(IMemory memory,Func<bool> authorized,Func<DateTime> clock=null){this.memory=memory;this.authorized=authorized;this.clock=clock??(()=>DateTime.UtcNow);Scope="freeroam";Scan();}
  void Permit(){var scan=memory as IScanState;if(scan!=null&&!scan.ScanComplete)throw new IOException("扫描不完整，禁止捕获/修改；请先导出诊断。");if(!Alive)throw new IOException("游戏会话已结束。");if(!authorized())throw new IOException("需要有效备份及本次单机确认；授权失效时不写入。");}
  public void Scan(){
   if(HasCode)throw new IOException("请先断开并恢复本工具代码，再重新扫描。");Sites.Clear();
   var hits=Contracts.Sites.ToDictionary(s=>s.Id,s=>new HashSet<long>());
   // Enumerate the image stream exactly once; overlap is deduplicated by absolute hit address.
   foreach(var region in memory.Code())foreach(var site in Contracts.Sites){var found=hits[site.Id];if(found.Count>=64)continue;foreach(var n in Contracts.Matches(region.Bytes,site.Pattern)){found.Add(region.Address+n+site.Offset);if(found.Count>=64)break;}}
   var state=memory as IScanState;bool complete=state==null||state.ScanComplete;
   foreach(var site in Contracts.Sites){var found=hits[site.Id];var r=new Resolution{Definition=site,Hits=found.Count,Status=found.Count==0?"未匹配":found.Count>1?"多处匹配，拒绝":"唯一候选"};
    if(found.Count==1){r.Address=found.First();try{r.Exact=memory.Read(r.Address,site.Expected.Length).SequenceEqual(site.Expected);}catch{r.Exact=false;}if(!r.Exact)r.Status="原始字节不符，拒绝";}
    if(!complete)r.Status="扫描不完整，禁止启用；已见候选 "+found.Count;
    Sites.Add(site.Id,r);
   }
  }
  Resolution RequireSite(string id){Resolution r;if(!Sites.TryGetValue(id,out r)||r.Hits!=1||!r.Exact)throw new IOException("接口 "+id+" 没有唯一、原字节匹配的候选；不套用固定地址。");return r;}
  Option Find(string id){var o=Contracts.Options.SingleOrDefault(x=>x.Id==id);if(o==null)throw new IOException("未知功能。");return o;}
  public void ChangeScope(string scope){if(!new[]{"freeroam","vehicle","spider","madness","hacking","drinking","cashrun","nvzn","alone","poker"}.Contains(scope))throw new IOException("未知活动模式。");StopAll();cached.Clear();foreach(var c in captures.Values){c.Pointer=0;c.Stable=0;c.Seen=DateTime.MinValue;c.HasHit=false;c.Generation++;}Scope=scope;}
  public string State(string id){PendingOnce q;if(pending.TryGetValue(id,out q))return "已排队，未执行；等待新心跳，剩余 "+Math.Max(0,(q.Expires-clock()).TotalSeconds).ToString("0")+"s";if(patches.ContainsKey(id))return "已启用候选代码";LiveValue v;if(active.TryGetValue(id,out v))return v.State;string s;return Messages.TryGetValue(id,out s)?s:"关闭 / 未验证";}
  public bool Enabled(string id){return active.ContainsKey(id)||patches.ContainsKey(id);}
  public void Observe(string optionId){
   Permit();var o=Find(optionId);if(o.Scope!=Scope)throw new IOException("先选择对应的实际活动，切换模式会停止全部修改。");
   if(o.Kind.Contains("patch")||o.Kind=="return_zero"){foreach(var id in o.Site.Split(new[] { ',' }, StringSplitOptions.None))RequireSite(id);Messages[o.Id]="唯一字节候选通过；尚未启用";return;}
   var r=RequireSite(o.Site);if(captures.ContainsKey(o.Site)){Messages[o.Id]="捕获已存在，不重复安装；"+CaptureSummary(o.Id);return;}if(r.Definition.CaptureRegister==null)throw new IOException("没有已核对的对象捕获契约。");
   long page=memory.AllocateNear(r.Address,4096);long slot=page+0x800;
   memory.WriteData(slot,new byte[16]);var code=Contracts.CaptureStub(r.Definition.CaptureRegister,slot,page,r.Address+r.Definition.Expected.Length,r.Definition.Expected);
   memory.WriteData(page,code);var jump=Contracts.Jump(r.Address,page,r.Definition.Expected.Length);
   memory.Patch(new[]{new Change{Address=r.Address,Before=r.Definition.Expected,After=jump}},new List<SpanRange>());
   captures[o.Site]=new Capture{Site=r,Page=page,CodeLength=code.Length,Seen=DateTime.MinValue,HookIntact=true,BufferReadable=true,Coherent=true};Messages[o.Id]="捕获已安装；触发对应菜单/活动后等待稳定对象，再启用";
  }
  bool Floating(Option o){return o.Kind.EndsWith("f32");}
  public double Current(string id){var o=Find(id);if(o.Kind.Contains("patch")||o.Kind=="return_zero")throw new IOException("代码开关没有数值回读。");var c=GetCapture(o);return ReadValue(o,c.Pointer);}
  double ReadValue(Option o,long pointer){byte[] data=memory.Read(pointer+o.Offset,o.Kind.EndsWith("u16")?2:4);double n=Floating(o)?BitConverter.ToSingle(data,0):o.Kind.EndsWith("u16")?BitConverter.ToUInt16(data,0):BitConverter.ToInt32(data,0);if(double.IsNaN(n)||double.IsInfinity(n)||n<o.Min||n>o.Max)throw new IOException("数值不符合已定义范围，对象可能不正确；拒绝写入。");return n;}
  void WriteValue(Option o,long pointer,double value){if(double.IsNaN(value)||double.IsInfinity(value)||value<o.Min||value>o.Max)throw new IOException("输入超出安全范围。");var bytes=Floating(o)?BitConverter.GetBytes((float)value):o.Kind.EndsWith("u16")?BitConverter.GetBytes(checked((ushort)value)):BitConverter.GetBytes(checked((int)value));memory.WriteData(pointer+o.Offset,bytes);}
  public void Enable(string id,double? custom=null){
   Permit();var o=Find(id);if(o.Scope!=Scope)throw new IOException("功能活动与手动选择模式不符。");if(o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_"))throw new IOException("一次性增加请使用“执行一次”，不是持续开关。");
   if(o.Kind.Contains("patch")||o.Kind=="return_zero"){
    if(patches.ContainsKey(id))return;var list=new List<Change>();foreach(var s in o.Site.Split(new[] { ',' }, StringSplitOptions.None)){var r=RequireSite(s);if(patches.Values.SelectMany(v=>v).Any(v=>RangesOverlap(v.Address,v.Before.Length,r.Address,r.Definition.Expected.Length)))throw new IOException("与已启用补丁重叠。");
     var bytes=o.Kind=="return_zero"?new byte[]{0x31,0xc0,0xc3,0x90}:Enumerable.Repeat((byte)0x90,r.Definition.Expected.Length).ToArray();list.Add(new Change{Address=r.Address,Before=r.Definition.Expected,After=bytes});}
    memory.Patch(list,new List<SpanRange>());patches[id]=list;Messages[id]="代码已应用；实际游戏效果待核验";return;
   }
   if(pending.Values.Any(q=>Find(q.Id).Site==o.Site&&Find(q.Id).Offset==o.Offset))throw new IOException("同字段有一次性请求排队，先取消再开启维持。");
   var capture=ReviewCapture(o);bool live=Fresh(capture);var reviewed=cached[o.Id];double current=live?ReadValue(o,capture.Pointer):reviewed.Value,value=custom??o.Value;
   if(new[]{"rep_good","rep_bad","police_detection","heat_hold"}.Contains(o.Id))value=o.Value;
   if(o.Kind=="freeze_f32")value=current;
   if(o.Kind=="capacity_f32")value=live?Capacity(o,capture.Pointer):reviewed.Capacity.Value;
   if(!Floating(o)&&value!=Math.Floor(value))throw new IOException("该项只接受整数。");if(value<o.Min||value>o.Max||double.IsNaN(value))throw new IOException("目标值超界。");
   foreach(var other in active.Where(a=>a.Value.Option.Site==o.Site&&a.Value.Option.Offset==o.Offset).Select(a=>a.Key).ToArray()){active.Remove(other);Messages[other]="同字段互斥项已关闭";}
   active[id]=new LiveValue{Option=o,Pointer=capture.Pointer,Generation=capture.Generation,ArmSequence=capture.Sequence,WaitNewHit=!live,Target=value,State=live?"已开启，等待本次回读":"已预置，尚未写入；切回游戏等同一对象的新心跳"};
  }
  static bool RangesOverlap(long a,int al,long b,int bl){return a<b+bl&&b<a+al;}
  double Capacity(Option o,long pointer){double max=BitConverter.ToSingle(memory.Read(pointer+(int)o.Value,4),0);if(double.IsNaN(max)||double.IsInfinity(max)||max<=0||max>o.Max)throw new IOException("容量字段无效。");return max;}
  public double Once(string id,double? custom=null){
   Permit();var o=Find(id);if(!(o.Kind.StartsWith("add_")||o.Kind.StartsWith("once_"))||o.Scope!=Scope)throw new IOException("一次性操作 / 活动不匹配。");
   if(active.Values.Any(a=>a.Option.Site==o.Site&&a.Option.Offset==o.Offset))throw new IOException("先关闭同一字段的无限/锁定开关，再执行独立增减。");
   var c=GetCapture(o);double before=ReadValue(o,c.Pointer),delta=custom??o.Value;if(double.IsNaN(delta)||double.IsInfinity(delta)||delta!=Math.Floor(delta)||Math.Abs(delta)>1000000)throw new IOException("增减量无效。");
   double after=o.Kind.StartsWith("once_")?o.Value:Math.Max(o.Min,Math.Min(o.Max,before+delta));WriteValue(o,c.Pointer,after);double readback=ReadValue(o,c.Pointer);Messages[id]="本次原始数值回读："+before+" → "+readback+"；不代表进度解锁";return readback;
  }
  public void Tick(){
   if(!Alive){active.Clear();CancelQueued();Messages["session"]="游戏会话已结束";return;}
   if((active.Count>0||patches.Count>0||pending.Count>0)&&!authorized()){active.Clear();CancelQueued();foreach(var id in patches.Keys.ToArray())try{Disable(id);}catch{Messages[id]="授权已失效，恢复代码失败，需退出游戏";}return;}
   Sample();ProcessQueued();foreach(var pair in active.ToArray()){
    var v=pair.Value;Capture c;try{
     if(!captures.TryGetValue(v.Option.Site,out c)||!Fresh(c)){v.State="等待新鲜捕获，当前不写入";continue;}
     if(c.Pointer!=v.Pointer||c.Generation!=v.Generation){active.Remove(pair.Key);Messages[pair.Key]="对象更换，已停止";continue;}
     if(v.WaitNewHit&&c.Sequence==v.ArmSequence){v.State="等待预置后的新心跳，当前不写入";continue;}v.WaitNewHit=false;
     double before=ReadValue(v.Option,v.Pointer),goal=v.Target;if(v.Option.Kind=="capacity_f32")goal=Capacity(v.Option,v.Pointer);
     if(v.Option.Kind.StartsWith("floor_")&&before>goal)goal=before;
     if(before!=goal)WriteValue(v.Option,v.Pointer,goal);
     v.State="启用候选 · 原始数值 "+ReadValue(v.Option,v.Pointer).ToString("0.###");
    }catch(Exception ex){active.Remove(pair.Key);Messages[pair.Key]="停止："+ex.Message;}
   }
  }
  public void Disable(string id){
   if(pending.Remove(id))Messages[id]="已取消排队，未执行该请求";
   if(active.Remove(id)){Messages[id]="已停止维持；不反向扣除数值";return;}
   List<Change> list;if(patches.TryGetValue(id,out list)){memory.Patch(list.Select(c=>new Change{Address=c.Address,Before=c.After,After=c.Before}).ToArray(),new List<SpanRange>());patches.Remove(id);Messages[id]="原代码已恢复";}
  }
  public void StopAll(){active.Clear();CancelQueued();var errors=new List<string>();foreach(var id in patches.Keys.ToArray())try{Disable(id);}catch(Exception ex){errors.Add(id+": "+ex.Message);}if(errors.Count>0)throw new IOException(string.Join("\n",errors));}
  public void Disconnect(){
   if(!Alive){active.Clear();CancelQueued();patches.Clear();captures.Clear();Dispose();return;}
   StopAll();var changes=captures.Values.Select(c=>new Change{Address=c.Site.Address,Before=Contracts.Jump(c.Site.Address,c.Page,c.Site.Definition.Expected.Length),After=c.Site.Definition.Expected}).ToArray();
   memory.Patch(changes,captures.Values.Select(c=>new SpanRange{Address=c.Page,Length=c.CodeLength}).ToArray());captures.Clear();Dispose();
  }
  public object Report(){return new {version="0.3.3-alpha",captures=Contracts.Options.Where(o=>captures.ContainsKey(o.Site)).Select(o=>Preview(o.Id)).ToArray(),queued=pending.Values.Select(q=>new {id=q.Id,scope=q.Scope,seconds_left=Math.Max(0,(q.Expires-clock()).TotalSeconds),generation=q.Generation}).ToArray(),scan=(memory as IScanState)==null?null:((IScanState)memory).Diagnostic,manual_scope=Scope,runtime_verified=false,sites=Sites.Values.Select(r=>new{id=r.Definition.Id,matches=r.Hits,rva=r.Hits==1?(long?)(r.Address-memory.ModuleBase):null,exact=r.Exact,historical=r.Definition.Historic}).ToArray(),features=Contracts.Options.Select(o=>new{id=o.Id,enabled=Enabled(o.Id),state=State(o.Id)}).ToArray()};}
  public void Dispose(){if(disposed)return;if(Alive&&HasCode)throw new IOException("还有本工具的捕获/补丁，请先恢复后断开。");disposed=true;memory.Dispose();}
 }
}
