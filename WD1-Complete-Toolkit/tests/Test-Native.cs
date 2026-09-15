// Isolated fake-process tests. Never open a real process or apply real game patches.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using WD1Kit.Native;
namespace WD1Kit.Tests {
 public class FakeMemory:IMemory {
  public long ModuleBase{get{return 0x180000000;}}public bool Alive{get;set;}=true;
  public readonly Dictionary<long,byte> Bytes=new Dictionary<long,byte>();public readonly Dictionary<string,long> Address=new Dictionary<string,long>();
  public readonly List<long> Pages=new List<long>();public bool RefusePatch;public int Writes,Patches,Reads;long next=0x190000000;
  readonly byte[] code;
  public FakeMemory(){code=Enumerable.Repeat((byte)0xcc,Contracts.Sites.Length*256+512).ToArray();int row=0;foreach(var s in Contracts.Sites){int off=128+row++*256;var raw=s.Pattern.Split(new[] { ' ' }, StringSplitOptions.None).Select(x=>x=="??"?(byte)0x7f:Convert.ToByte(x,16)).ToArray();Buffer.BlockCopy(raw,0,code,off,raw.Length);Address[s.Id]=ModuleBase+off+s.Offset;}Put(ModuleBase,code);}
  public void Put(long p,byte[] b){for(int i=0;i<b.Length;i++)Bytes[p+i]=b[i];}
  public byte[] Read(long p,int n){Reads++;var b=new byte[n];for(int i=0;i<n;i++){byte v;if(!Bytes.TryGetValue(p+i,out v))throw new IOException("fixture inaccessible");b[i]=v;}return b;}
  public IEnumerable<CodeRegion> Code(){return new List<CodeRegion>{new CodeRegion{Address=ModuleBase,Bytes=(byte[])code.Clone()}};}
  public void WriteData(long p,byte[] b){Writes++;Put(p,b);}
  public long AllocateNear(long p,int size){long a=next;next+=0x10000;Pages.Add(a);Put(a,new byte[size]);return a;}
  public void Patch(IList<Change> changes,IList<SpanRange> protectedRanges){if(RefusePatch)throw new IOException("fixture busy thread");foreach(var c in changes)if(!Read(c.Address,c.Before.Length).SequenceEqual(c.Before))throw new IOException("fixture foreign code");foreach(var c in changes)Put(c.Address,c.After);Patches++;}
  public void Capture(long page,long ptr,long seq){Put(page+0x800,BitConverter.GetBytes(ptr));Put(page+0x808,BitConverter.GetBytes(seq));}
  public void Dispose(){Alive=false;}
 }
 public static class NativeTests {
  static int count;static void Check(bool b,string n){if(!b)throw new Exception("FAIL "+n);Console.WriteLine("PASS "+n);count++;}
  static void Fails(Action a,string n){bool b=false;try{a();}catch{b=true;}Check(b,n);}
  static void Fill(FakeMemory m,long p,int offset,int value){m.Put(p,new byte[8192]);m.Put(p+offset,BitConverter.GetBytes(value));}
  static void Warm(Engine e,FakeMemory m,long page,long pointer,long seq=1){m.Capture(page,pointer,seq);for(int i=0;i<3;i++)e.Tick();}
  public static int Run(){
   Check(Contracts.Matches(new byte[]{1,2,3,1,9,3},"01 ?? 03").SequenceEqual(new[]{0,3}),"wildcard finds all occurrences");
   Check(Contracts.Matches(new byte[]{1,2},"01 02 03").Count==0,"pattern longer than section handled");
   Check(Contracts.Matches(Enumerable.Repeat((byte)0xaa,1000).ToArray(),"AA").Count==64,"ambiguous results bounded");
   Fails(()=>Contracts.Jump(0x180000000,0x300000000,5),"out-of-range rel32 jump rejected");
   var jump=Contracts.Jump(0x180000000,0x180000100,8);Check(jump[0]==0xe9&&BitConverter.ToInt32(jump,1)==0xfb&&jump.Skip(5).All(x=>x==0x90),"rel32 jump and padding correct");
   foreach(var reg in new[]{"rax","rcx","rdx","rbx","r14"}){var b=Contracts.CaptureStub(reg,0x190000800,0x190000000,0x180000005,new byte[]{0xf3,0x0f,0x10,0x41,0x18});Check(b.Take(5).SequenceEqual(new byte[]{0x9c,0x41,0x53,0x49,0xbb})&&b.Contains((byte)0x9d),"capture preserves flags and scratch register "+reg);}
   Fails(()=>Contracts.CaptureStub("rip",0,0,0,new byte[]{0}),"unverified capture register rejected");
   {
    var m=new FakeMemory();var e=new Engine(m,()=>false);Check(e.Sites.Values.All(x=>x.Hits==1&&x.Exact),"fixture signatures all uniquely validated");Check(m.Writes==0&&m.Patches==0,"connect/scan zero writes");Fails(()=>e.Enable("no_reload"),"no authorization refuses patch");Fails(()=>e.Observe("money_floor"),"no authorization refuses capture");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);e.Enable("no_reload");Check(e.Enabled("no_reload"),"individual patch enabled");Check(m.Read(m.Address["reload"],6).All(x=>x==0x90),"no-reload candidate instruction suppressed");e.Disable("no_reload");Check(m.Read(m.Address["reload"],6).SequenceEqual(Contracts.Sites.Single(x=>x.Id=="reload").Expected),"disable restores exact original bytes");
    e.Enable("inventory_infinite");Check(e.Enabled("inventory_infinite")&&!e.Enabled("money_floor"),"unlimited inventory distinct from money and increase");e.Disable("inventory_infinite");
    e.ChangeScope("drinking");e.Enable("drink_timer");Check(m.Read(m.Address["drink_a"],4).All(x=>x==0x90)&&m.Read(m.Address["drink_b"],4).All(x=>x==0x90),"drinking timer uses both admitted paths");e.Disable("drink_timer");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);m.RefusePatch=true;Fails(()=>e.Enable("no_reload"),"busy thread refusal propagated");Check(!e.Enabled("no_reload"),"failed patch cannot show enabled");m.RefusePatch=false;m.Put(m.Address["reload"],new byte[]{0x90});Fails(()=>e.Enable("no_reload"),"foreign-modified instructions refused");e.Disconnect();
   }
   {
    var m=new FakeMemory();bool allowed=true;var e=new Engine(m,()=>allowed);e.Enable("no_reload");allowed=false;e.Tick();Check(!e.Enabled("no_reload"),"expired authorization restores code switches");e.Disconnect();
   }
   {
    var m=new FakeMemory();var now=DateTime.UtcNow;var e=new Engine(m,()=>true,()=>now);Fails(()=>e.Enable("money_floor"),"unknown object cannot activate data writes");e.Observe("money_floor");Check(m.Patches==1&&!e.Enabled("money_floor"),"capture alone does not enable money");long p=0x40000000;Fill(m,p,0x9c,40);m.Put(p+0xa0,BitConverter.GetBytes(2));m.Put(p+0xa8,BitConverter.GetBytes(100));Warm(e,m,m.Pages[0],p);
    Check(e.Current("money_floor")==40,"readback uses captured current object");e.Enable("money_floor",1000);e.Tick();Check(BitConverter.ToInt32(m.Read(p+0x9c,4),0)==1000,"money floor maintained");Check(BitConverter.ToInt32(m.Read(p+0xa0,4),0)==2,"money lock leaves skill field untouched");Fails(()=>e.Once("cash_add",10),"increase remains separate and blocked only by conflicting lock");e.Disable("money_floor");Check(e.Once("cash_add",25)==1025,"increase works after independent lock off");Check(!e.Enabled("money_floor"),"increase does not turn on unlimited money");
    e.Enable("skill_floor",99);e.Tick();Check(e.Current("skill_floor")==99,"normal skill floor distinct from money");Check(e.Once("xp_add",1000)==1100,"independent experience action");
    m.Capture(m.Pages[0],p+0x10000,2);e.Tick();Check(!e.Enabled("skill_floor"),"pointer change stops affected writers");
    Warm(e,m,m.Pages[0],p,3);e.Enable("money_floor",2000);now=now.AddSeconds(3);e.Tick();Check(e.State("money_floor").Contains("等待"),"stale capture suppresses writes");e.Disable("money_floor");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);e.Observe("rep_good");long p=0x41000000;Fill(m,p,0x10,20);Warm(e,m,m.Pages[0],p);e.Enable("rep_good");e.Tick();Check(e.Current("rep_up")==600,"good reputation fixed to bounded +600");e.Enable("rep_bad");e.Tick();Check(!e.Enabled("rep_good")&&e.Current("rep_up")==-600,"good/bad mutually exclusive not two conflicting writers");e.Disable("rep_bad");Check(e.Once("rep_up",50)==-550,"reputation increase independent");Check(e.Once("rep_down",-1000)==-600,"reputation increment clamped to valid range");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);e.Observe("heat_up");long p=0x42000000;m.Put(p,new byte[100]);m.Put(p+0x0c,BitConverter.GetBytes((ushort)50));m.Put(p+0x0e,new byte[]{0xaa,0xbb});Warm(e,m,m.Pages[0],p);Check(e.Once("heat_up",10)==60,"heat uses 16-bit value");Check(m.Read(p+0x0e,2).SequenceEqual(new byte[]{0xaa,0xbb}),"heat update preserves adjacent fields");Check(e.Once("heat_clear",0)==0,"clear heat is one shot");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);e.Observe("battery_full");long p=0x43000000;m.Put(p,new byte[512]);m.Put(p+0xe8,BitConverter.GetBytes(5f));m.Put(p+0xec,BitConverter.GetBytes(1f));Warm(e,m,m.Pages[0],p);e.Enable("battery_full");e.Tick();Check(e.Current("battery_full")==5,"battery uses separate capacity field");e.Disable("battery_full");m.Put(p+0xec,BitConverter.GetBytes(float.NaN));Fails(()=>e.Enable("battery_full"),"NaN object rejected");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);Fails(()=>e.Enable("spider_timer"),"wrong manual scope refuses activity feature");e.ChangeScope("spider");e.Observe("spider_timer");long p=0x44000000;m.Put(p,new byte[128]);m.Put(p+0x0c,BitConverter.GetBytes(42f));Warm(e,m,m.Pages[0],p);e.Enable("spider_timer");m.Put(p+0x0c,BitConverter.GetBytes(41f));m.Capture(m.Pages[0],p,2);e.Tick();Check(e.Current("spider_timer")==42,"timer freezes captured value not global game time");e.ChangeScope("madness");Check(!e.Enabled("spider_timer"),"mode change stops prior activity");Fails(()=>e.Enable("madness_timer"),"mode change requires fresh capture evidence");e.Disconnect();
   }
   {
    var m=new FakeMemory();var e=new Engine(m,()=>true);e.Observe("money_floor");Fails(()=>e.Dispose(),"cannot dispose while live capture remains");e.Disconnect();Check(!m.Alive,"disconnect restores then releases handle");
   }
   Console.WriteLine("NATIVE_FIXTURE_CHECKS="+count);return count;
  }
 }
}
