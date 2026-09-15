// Synthetic PE headers and mapped pages only. No real game, native calls, or memory dumps.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using WD1Kit.Native;
namespace WD1Kit.Tests {
 public static class ImageScanTests {
  static int count;static void Check(bool b,string name){if(!b)throw new Exception("FAIL "+name);Console.WriteLine("PASS "+name);count++;}
  static void Fails(Action action,string name){bool caught=false;try{action();}catch{caught=true;}Check(caught,name);}
  static SectionInfo Section(uint rva,uint size,uint raw=0,uint flags=0x60000020){return new SectionInfo{Rva=rva,VirtualSize=size,RawSize=raw,Flags=flags,Name=".text"};}
  static byte[] Header(uint imageSize,params SectionInfo[] sections){var b=new byte[4096];Action<int,byte[]> put=(p,x)=>Buffer.BlockCopy(x,0,b,p,x.Length);b[0]=0x4d;b[1]=0x5a;put(0x3c,BitConverter.GetBytes(0x80));put(0x80,BitConverter.GetBytes(0x4550));put(0x84,BitConverter.GetBytes((ushort)0x8664));put(0x86,BitConverter.GetBytes((ushort)sections.Length));put(0x94,BitConverter.GetBytes((ushort)0xf0));int opt=0x98;put(opt,BitConverter.GetBytes((ushort)0x20b));put(opt+32,BitConverter.GetBytes(0x1000));put(opt+56,BitConverter.GetBytes(imageSize));put(opt+60,BitConverter.GetBytes(0x1000));int i=0;foreach(var s in sections){int p=opt+0xf0+i++*40;put(p,System.Text.Encoding.ASCII.GetBytes(".text"));put(p+8,BitConverter.GetBytes(s.VirtualSize));put(p+12,BitConverter.GetBytes(s.Rva));put(p+16,BitConverter.GetBytes(s.RawSize));put(p+36,BitConverter.GetBytes(s.Flags));}return b;}
  static ImageInfo Parse(byte[] header){return PeImage.Parse((p,n)=>header.Skip((int)p).Take(n).ToArray(),"fixture");}
  sealed class Reader:IImagePageReader {
   public const long Base=0x180000000;public readonly List<PageInfo> Pages=new List<PageInfo>();public int Reads,MaxRead;public long Total;public long FailAt=-1;public bool ShortRead;public Func<long,int,byte[]> Produce;
   public void Add(long offset,ulong length,uint protect=0x20,uint state=0x1000,uint type=0x1000000,bool same=true){Pages.Add(new PageInfo{Address=Base+offset,AllocationBase=same?Base:Base+0x50000000,Length=length,Protect=protect,State=state,Type=type});}
   public PageInfo Query(long p){var x=Pages.FirstOrDefault(r=>p>=r.Address&&p<r.Address+(long)r.Length);if(x==null)throw new IOException("fixture query failure");return x;}
   public byte[] Read(long p,int n){Reads++;MaxRead=Math.Max(MaxRead,n);Total+=n;if(p==FailAt)throw new IOException("fixture read failure");if(ShortRead)return new byte[Math.Max(0,n-1)];return Produce==null?new byte[n]:Produce(p,n);}
  }
  sealed class ChunkedMemory:IMemory,IScanState {
   public FakeMemory Inner=new FakeMemory();public bool ScanComplete {get;set;}=true;public ScanDiagnostic Diagnostic {get;private set;}=new ScanDiagnostic();public int Enumerations;
   public long ModuleBase{get{return Inner.ModuleBase;}}public bool Alive{get{return Inner.Alive;}}
   public IEnumerable<CodeRegion> Code(){Enumerations++;var original=Inner.Code().Single();const int size=256;for(int p=0;p<original.Bytes.Length;p+=size){int start=Math.Max(0,p-64),end=Math.Min(original.Bytes.Length,p+size);yield return new CodeRegion{Address=original.Address+start,Bytes=original.Bytes.Skip(start).Take(end-start).ToArray()};}}
   public byte[] Read(long a,int n){return Inner.Read(a,n);}public void WriteData(long a,byte[] b){Inner.WriteData(a,b);}public long AllocateNear(long a,int n){return Inner.AllocateNear(a,n);}public void Patch(IList<Change> c,IList<SpanRange> p){Inner.Patch(c,p);}public void Dispose(){Inner.Dispose();}
  }
  public static int Run(){
   var basic=Parse(Header(0x6000,Section(0x1000,0x3000)));Check(basic.Machine==0x8664&&basic.Magic==0x20b,"PE32+ machine and magic parsed");Check(basic.SizeOfImage==0x6000&&basic.Sections[0].Rva==0x1000,"SizeOfImage and section RVA parsed separately");
   var raw=Parse(Header(0x5000,Section(0x1000,0,0x2000)));Check(PeImage.Plan(raw,new ScanDiagnostic()).Single().Length==0x2000,"zero VirtualSize falls back to raw size");
   var headers=Header(0x6000,Section(0x1000,0x2000));headers[0]=0;Fails(()=>Parse(headers),"bad DOS magic rejected");headers=Header(0x6000,Section(0x1000,0x2000));headers[0x98]=0x0b;headers[0x99]=0x01;Fails(()=>Parse(headers),"PE32 optional header cannot masquerade as PE32+");
   ImageInfo observed=null;Fails(()=>PeImage.Parse((p,n)=>Header(0xffffffff,Section(0x1000,0x2000)).Skip((int)p).Take(n).ToArray(),"fixture",x=>observed=x),"oversized image span remains bounded");Check(observed!=null&&observed.SizeOfImage==0xffffffff,"invalid image size still retained for diagnosis");
   {
    var d=new ScanDiagnostic();var image=Parse(Header(0x9000,Section(0x1000,0x3000),Section(0x2000,0x3000)));var ranges=PeImage.Plan(image,d);Check(ranges.Count==1&&ranges[0].Length==0x4000,"overlapping sections normalized without double counting");Check(d.Warnings.Contains("OVERLAPPING_SECTIONS_NORMALIZED"),"normalization recorded");
   }
   {
    var d=new ScanDiagnostic();var image=Parse(Header(0x6000,Section(0x1000,0x2000),Section(0x5000,0xffffffff)));var ranges=PeImage.Plan(image,d);Check(ranges.Count==1&&d.FailureCount==1,"overflow-like section size cannot wrap into valid range");Check(d.ReadFailures[0].Code=="SECTION_OUTSIDE_VERIFIED_IMAGE","section failure distinguishes precise reason");
   }
   {
    var r=new Reader();r.Add(0x1000,0x3000);var d=new ScanDiagnostic{ReportedModuleBytes=0x2000};var scan=new ImageScanSession(r,Reader.Base,basic,d,1024);Check(!scan.Contains(Reader.Base+0x3000,8),"patch range unavailable before complete snapshot");int chunks=0;foreach(var b in scan.ReadCode())chunks++;
    Check(d.Complete&&chunks>1,"mapped code may extend beyond stale reported module size");Check(scan.Contains(Reader.Base+0x3000,8),"patch bounds use validated scanned image rather than module-size guess");Check(!scan.Contains(Reader.Base+0x5000,8),"unscanned image bytes still forbidden");Check(!scan.Contains(Reader.Base-1,8),"address before image forbidden");
   }
   {
    const uint large=70*1024*1024;var image=Parse(Header(large+0x2000,Section(0x1000,large)));var r=new Reader();r.Add(0x1000,large);var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,image,d);
    int n=0;foreach(var b in scan.ReadCode())n++;
    Check(d.Complete&&d.ReadBytes==large,"legitimate executable extent above old 64MiB limit scanned");Check(r.MaxRead<=ImageScanSession.DefaultChunkBytes&&n==35,"large extent read in bounded 2MiB chunks, not one large allocation");
   }
   {
    var r=new Reader();r.Add(0x1000,0x3000);var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,basic,d,1024,64,1500);Fails(()=>scan.ReadCode().ToList(),"actual read budget still enforced");Check(!scan.Contains(Reader.Base+0x1000,4),"budget-limited partial scan cannot authorize code edits");
   }
   foreach(string problem in new[]{"guard","noaccess","foreign","private"}){
    var r=new Reader();uint protect=problem=="guard"?0x120u:problem=="noaccess"?0x01u:0x20u;r.Add(0x1000,0x3000,protect,0x1000,problem=="private"?0x20000u:0x1000000u,problem!="foreign");var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,basic,d);
    Fails(()=>scan.ReadCode().ToList(),"no valid code read for "+problem);Check(r.Reads==0&&!d.Complete,"not reading forbidden/foreign page: "+problem);
   }
   {
    var image=Parse(Header(0x5000,Section(0x1000,0x1000),Section(0x3000,0x1000,0,0x62000020)));var r=new Reader();r.Add(0x1000,0x1000);r.Add(0x3000,0x1000,1,0x2000);var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,image,d);scan.ReadCode().ToList();Check(d.Complete&&d.SkippedBytes==0x1000,"explicit discardable section may be absent without inventing bytes");Check(!scan.Contains(Reader.Base+0x3000,8),"discarded span never writable through scanned-code gate");
   }
   {
    var r=new Reader();r.Add(0x1000,0x3000);r.FailAt=Reader.Base+0x1400;var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,basic,d,1024);scan.ReadCode().ToList();Check(d.ReadFailures.Any(x=>x.Code=="READ_EXECUTABLE_CHUNK_FAILED")&&!d.Complete,"read race yields incomplete report instead of success");Check(!scan.Contains(Reader.Base+0x1000,4),"read race prevents partial-uniqueness writes");
   }
   {
    var r=new Reader();r.Add(0x1000,0x3000);r.ShortRead=true;var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,basic,d,1024);Fails(()=>scan.ReadCode().ToList(),"short reads not padded into artificial code");Check(!d.Complete,"short reads cannot mark scan complete");
   }
   {
    var r=new Reader();r.Add(0x1000,0x1000);var d=new ScanDiagnostic();var scan=new ImageScanSession(r,Reader.Base,basic,d);Fails(()=>scan.ReadCode().ToList(),"unmapped tail produces bounded query failure");Check(d.ReadFailures.Any(x=>x.Code=="VIRTUAL_QUERY_FAILED"),"query failure retained in diagnostic");
   }
   {
    var image=Parse(Header(0x2000,Section(0x1000,0x200)));var bytes=new byte[512];var pattern=new byte[]{0x11,0x22,0x33,0x44,0x55,0x66};Buffer.BlockCopy(pattern,0,bytes,126,pattern.Length);
    var r=new Reader();r.Add(0x1000,0x200);r.Produce=(p,n)=>bytes.Skip((int)(p-Reader.Base-0x1000)).Take(n).ToArray();var scan=new ImageScanSession(r,Reader.Base,image,new ScanDiagnostic(),128,64);var hits=new HashSet<long>();foreach(var region in scan.ReadCode())foreach(var n in Contracts.Matches(region.Bytes,"11 22 33 44 55 66"))hits.Add(region.Address+n);
    Check(hits.SetEquals(new[]{Reader.Base+0x1000+126}),"pattern crossing chunk boundary preserved exactly once");
   }
   {
    var m=new ChunkedMemory();var e=new Engine(m,()=>true);Check(m.Enumerations==1,"engine consumes code iterator exactly once");Check(e.Sites.Values.All(x=>x.Hits==1&&x.Exact),"overlap never creates false duplicate AOB hits");e.Disconnect();
   }
   {
    var m=new ChunkedMemory{ScanComplete=false};var e=new Engine(m,()=>true);Fails(()=>e.Enable("no_reload"),"incomplete scan blocks ordinary code patch");Fails(()=>e.Observe("money_floor"),"incomplete scan blocks capture installation");Check(m.Inner.Writes==0&&m.Inner.Patches==0,"incomplete scan stays truly read-only");e.Disconnect();
   }
   {
    var d=new ScanDiagnostic{Stage="PLAN_EXECUTABLE_RANGES",ReportedModuleBytes=1024,Disk=basic};d.Failure(new ScanException("SECTION_OUTSIDE_VERIFIED_IMAGE","fixture"));string text=Files.Json.Serialize(d);
    Check(text.Contains("SizeOfImage")&&text.Contains("SECTION_OUTSIDE_VERIFIED_IMAGE"),"failure has exportable numeric header and precise code");Check(!text.Contains("BaseAddress")&&!text.Contains("SourceDirectory"),"diagnostic contains no absolute pointer/path fields");
   }
   var mixedReader=new Reader();mixedReader.Add(0x1000,0x1000);mixedReader.Add(0x2000,0x2000,1);var mixedReport=new ScanDiagnostic();var mixedScan=new ImageScanSession(mixedReader,Reader.Base,basic,mixedReport);mixedScan.ReadCode().ToList();
   Check(!mixedReport.Complete&&mixedReport.ReadBytes==0x1000,"NOACCESS inside executable section cannot make a partial snapshot look complete");
   Check(!mixedScan.Contains(Reader.Base+0x1000,4),"readable prefix cannot authorize writes when another code page is NOACCESS");
   var failed=new ScanDiagnostic{Stage="VERIFIED_DISK_PE"};failed.Failure(new ScanException("PE_IMAGE_BUDGET","fixture"));string exported=Files.Json.Serialize(NativeForm.ExportPayload(null,failed));
   Check(exported.Contains("\"connected\":false")&&exported.Contains("PE_IMAGE_BUDGET"),"failed connection export works with no Engine instance");
   Fails(()=>NativeForm.ExportPayload(null,null),"empty diagnostic cannot fake a connection attempt");
   Console.WriteLine("IMAGE_SCAN_FIXTURE_CHECKS="+count);return count;
  }
 }
}
