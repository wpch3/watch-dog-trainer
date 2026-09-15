// Reproduces Alt-Tab/pause freshness loss with a controllable clock and fake process memory.
using System;
using System.IO;
using System.Linq;
using WD1Kit.Native;
namespace WD1Kit.Tests {
 public static class CaptureTests {
  static int count;static void Check(bool b,string n){if(!b)throw new Exception("FAIL "+n);Console.WriteLine("PASS "+n);count++;}
  static void Fails(Action a,string code,string n){Exception error=null;try{a();}catch(Exception e){error=e;}Check(error!=null&&(code==null||error.Message.Contains(code)),n);}
  sealed class Case:IDisposable {
   public FakeMemory M=new FakeMemory();public DateTime Now=new DateTime(2026,9,14,12,0,0,DateTimeKind.Utc);public bool Authorized=true;public Engine E;public long P=0x45000000;public long Page;
   public Case(){E=new Engine(M,()=>Authorized,()=>Now);M.Put(P,new byte[8192]);M.Put(P+0x9c,BitConverter.GetBytes(500));M.Put(P+0xa0,BitConverter.GetBytes(3));M.Put(P+0xa8,BitConverter.GetBytes(1000));}
   public void Observe(){E.Observe("cash_add");Page=M.Pages.Last();}
   public void Warm(long sequence=1){M.Capture(Page,P,sequence);for(int i=0;i<3;i++)E.Tick();}
   public int Cash {get{return BitConverter.ToInt32(M.Read(P+0x9c,4),0);}}
   public void Dispose(){E.Disconnect();}
  }
  public static int Run(){
   using(var f=new Case()){
    Check(f.E.Preview("cash_add").Code=="NOT_INSTALLED","not-installed state explicit");Fails(()=>f.E.Current("cash_add"),"NOT_INSTALLED","strict getter explains missing installation");
    f.Observe();Check(f.E.Preview("cash_add").Code=="HOOK_NOT_HIT","installed but never executed distinct from stale");f.E.Tick();Check(f.E.Preview("cash_add").HitCount==0,"zero execution count preserved");
    int writes=f.M.Writes;Fails(()=>f.E.QueueOnce("cash_add",100),"HOOK_NOT_HIT","no-hit pointer cannot be queued");Check(f.M.Writes==writes,"diagnostic/failed queue creates no game write");
    f.M.Capture(f.Page,f.P,1);f.E.Tick();Check(f.E.Preview("cash_add").Code=="POINTER_NOT_STABLE","first sample not falsely stable");f.E.Tick();f.E.Tick();var p=f.E.Preview("cash_add");Check(p.Code=="READY_LIVE"&&p.Value==500,"three samples yield current typed value");
    f.Now=f.Now.AddSeconds(5);f.E.Tick();p=f.E.Preview("cash_add");Check(p.Code=="CACHED_PAUSED_OR_STALE"&&p.CachedOnly&&p.Value==500,"Alt-Tab stale state retains labeled cached cash");
    int reads=f.M.Reads;f.E.Preview("cash_add");Check(f.M.Reads==reads,"paused preview uses stored scalar, not stale pointer memory reads");
    Check(p.SecondsSinceHit==5&&p.HitCount==1,"age and heartbeat explain freshness failure");
    Fails(()=>f.E.Once("cash_add",100),"CACHED_PAUSED_OR_STALE","old immediate write remains blocked when stale");
    int before=f.M.Writes;f.E.QueueOnce("cash_add",100);Check(f.E.HasPending&&f.M.Writes==before&&f.Cash==500,"queuing stale reviewed object does not write immediately");
    Fails(()=>f.E.QueueOnce("cash_add",100),null,"duplicate queue cannot accumulate increments");
    f.E.Tick();Check(f.Cash==500,"queue waits while game remains paused");
    f.Now=f.Now.AddSeconds(1);f.Warm(2);Check(!f.E.HasPending&&f.Cash==600,"new same-object heartbeat executes exactly once");
    f.Warm(3);Check(f.Cash==600,"further heartbeats do not repeat queued increase");
    Check(!f.E.Enabled("money_floor"),"one-time queue never enables unlimited cash");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",25);f.E.Tick();Check(f.Cash==500,"even fresh queue requires a heartbeat after confirmation");f.Warm(2);Check(f.Cash==525,"next heartbeat releases fresh queued action");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",100);f.E.CancelQueued();f.Warm(2);Check(f.Cash==500&&!f.E.HasPending,"cancel stops queued mutation");
    f.E.QueueOnce("cash_add",100);f.E.StopAll();f.Warm(3);Check(f.Cash==500,"STOP cancels pending actions");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",100);f.Now=f.Now.AddSeconds(31);f.E.Tick();Check(!f.E.HasPending&&f.Cash==500&&f.E.State("cash_add").Contains("超时"),"queue expires after 30 seconds without a write");f.Warm(2);Check(f.Cash==500,"late heartbeat never replays an expired action");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",100);long other=f.P+0x10000;f.M.Put(other,new byte[8192]);f.M.Put(other+0x9c,BitConverter.GetBytes(800));f.M.Capture(f.Page,other,2);f.E.Tick();Check(!f.E.HasPending&&f.Cash==500&&BitConverter.ToInt32(f.M.Read(other+0x9c,4),0)==800,"pointer replacement cancels instead of rebinding queued money");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",100);f.Authorized=false;f.M.Capture(f.Page,f.P,2);f.E.Tick();Check(f.Cash==500&&!f.E.HasPending,"authorization expiry cancels queued action");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.Now=f.Now.AddSeconds(5);f.E.Tick();int before=f.M.Writes;f.E.Enable("money_floor",1000);f.E.Tick();Check(f.E.Enabled("money_floor")&&f.M.Writes==before&&f.Cash==500,"stale continuous option can be armed without stale mutation");f.Warm(2);Check(f.Cash==1000,"continuous option starts only after fresh same-object hit");f.E.Disable("money_floor");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.Now=f.Now.AddSeconds(121);f.E.Tick();Check(f.E.Preview("cash_add").Value==500&&f.E.Preview("cash_add").Code=="CACHED_EXPIRED","old diagnostic value remains visible but labeled expired");Fails(()=>f.E.QueueOnce("cash_add",100),"CACHED_EXPIRED","review timeout cannot authorize queue");Fails(()=>f.E.Enable("money_floor",1000),"CACHED_EXPIRED","review timeout cannot arm continuous mutation");
   }
   using(var f=new Case()){
    f.Observe();f.M.Capture(f.Page,f.P+4,1);f.E.Tick();Check(f.E.Preview("cash_add").Code=="POINTER_ALIGNMENT_REJECTED","pointer alignment failure no longer hidden as generic freshness");
    f.M.Capture(f.Page,0,2);f.E.Tick();Check(f.E.Preview("cash_add").Code=="HIT_WITH_NULL_POINTER","null pointer after hit identified separately");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.M.Bytes.Remove(f.Page+0x800);f.E.Tick();Check(f.E.Preview("cash_add").Code=="BUFFER_UNREADABLE"&&f.E.Preview("cash_add").ReadFailures==1,"capture buffer failure exported explicitly");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",100);long site=f.M.Address["resources"];var jump=f.M.Read(site,7);f.M.Put(site,new byte[]{0x90});f.E.Tick();Check(f.E.Preview("cash_add").Code=="HOOK_CHANGED"&&!f.E.HasPending&&f.Cash==500,"changed hook cancels queue rather than trusting cached object");f.M.Put(site,jump);
   }
   using(var f=new Case()){
    f.Observe();f.Warm();f.E.QueueOnce("cash_add",100);f.E.ChangeScope("spider");f.M.Capture(f.Page,f.P,2);f.E.Tick();Check(!f.E.HasPending&&f.Cash==500,"scope change cancels queued action");
   }
   using(var f=new Case()){
    f.Observe();f.Warm();int n=f.M.Patches;f.E.Observe("cash_add");Check(f.M.Patches==n,"repeated capture click does not add another hook");
    string json=Files.Json.Serialize(f.E.Report());Check(json.Contains("READY_LIVE")&&json.Contains("HitCount")&&json.Contains("StableSamples")&&json.Contains("SecondsSinceHit"),"report contains actionable capture telemetry");Check(!json.Contains("Page")&&!json.Contains("Pointer\":")&&!json.Contains("storage"),"capture telemetry omits raw pointer and buffer addresses");
   }
   Console.WriteLine("CAPTURE_FIXTURE_CHECKS="+count);return count;
  }
 }
}
