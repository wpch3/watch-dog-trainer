// Original bounded PE/image-page scanner. All addresses in exported diagnostics are RVAs, not pointers.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Diagnostics;
namespace WD1Kit.Native {
 public class SectionInfo {
  public int Index;public string Name;public uint Rva,VirtualSize,RawSize,Flags;
  public bool Executable {get{return (Flags&0x20000000)!=0;}}
  public bool Discardable {get{return (Flags&0x02000000)!=0;}}
  public ulong Length {get{return VirtualSize!=0?VirtualSize:RawSize;}}
 }
 public class ImageInfo {
  public string Origin;public uint SizeOfImage,SizeOfHeaders,SectionAlignment;public int NtOffset,OptionalSize;
  public ushort Machine,Magic;public List<SectionInfo> Sections=new List<SectionInfo>();
 }
 public class RvaRange {public ulong Start,Length;public bool Discardable;public ulong End {get{return checked(Start+Length);}}}
 public class PageInfo {public long Address,AllocationBase;public ulong Length;public uint State,Protect,Type;}
 public class PageNote {public long Rva;public ulong Length;public uint State,Protect,Type;public bool SameAllocation;public string Decision;}
 public class ReadNote {public long Rva;public int Length,Win32Error;public string Code;}
 public class ScanDiagnostic {
  public string Product="WD1KIT",Version="0.3.3-alpha",Utc=DateTime.UtcNow.ToString("o"),Stage="NOT_STARTED",Outcome="NOT_STARTED",ErrorType="",ErrorCode="";
  public bool FingerprintsMatched,ProcessPathMatched,EnginePathMatched,Complete;
  public long ReportedModuleBytes,PlannedExecutableBytes,ReadBytes,SkippedBytes;
  public int PagesQueried,ChunksRead,FailureCount;public bool PageListTruncated;
  public ImageInfo Disk,Runtime;public List<string> Warnings=new List<string>();public List<PageNote> Pages=new List<PageNote>();public List<ReadNote> ReadFailures=new List<ReadNote>();
  public void Warn(string code){if(!Warnings.Contains(code)&&Warnings.Count<64)Warnings.Add(code);}
  public void Page(PageNote note){PagesQueried++;if(Pages.Count<1024)Pages.Add(note);else PageListTruncated=true;}
  public void Problem(string code,long rva=0,int length=0,int nativeError=0){Complete=false;FailureCount++;if(ReadFailures.Count<128)ReadFailures.Add(new ReadNote{Code=code,Rva=rva,Length=length,Win32Error=nativeError});}
  public void Failure(Exception ex){Complete=false;Outcome="FAILED";ErrorType=ex.GetType().Name;var e=ex as ScanException;ErrorCode=e==null?"CONNECT_EXCEPTION":e.Code;}
 }
 public sealed class ScanException:IOException {public string Code {get;private set;}public ScanException(string code,string message):base(message+" ["+code+"]"){Code=code;}}
 public interface IImagePageReader {PageInfo Query(long address);byte[] Read(long address,int length);}
 public interface IScanState {bool ScanComplete {get;}ScanDiagnostic Diagnostic {get;}}
 public static class PeImage {
  public const long MaxHeaderBytes=1024*1024;public const ulong MaxImageSpan=1024UL*1024*1024;
  static byte[] HeaderRead(Func<long,int,byte[]> read,long offset,int count){if(offset<0||count<1||offset+count>MaxHeaderBytes)throw new ScanException("PE_HEADER_BOUNDS","PE头超出有界读取范围");var b=read(offset,count);if(b==null||b.Length!=count)throw new ScanException("PE_HEADER_SHORT","PE头读取不完整");return b;}
  public static ImageInfo Parse(Func<long,int,byte[]> read,string origin,Action<ImageInfo> observed=null){
   var h=HeaderRead(read,0,64);if(h[0]!=0x4d||h[1]!=0x5a)throw new ScanException("PE_DOS_SIGNATURE","PE DOS签名不符");
   int nt=BitConverter.ToInt32(h,0x3c);if(nt<64||nt>MaxHeaderBytes-24)throw new ScanException("PE_NT_OFFSET","PE NT头偏移异常");
   var coff=HeaderRead(read,nt,24);if(BitConverter.ToUInt32(coff,0)!=0x4550)throw new ScanException("PE_NT_SIGNATURE","PE NT签名不符");
   ushort machine=BitConverter.ToUInt16(coff,4),count=BitConverter.ToUInt16(coff,6),optSize=BitConverter.ToUInt16(coff,20);
   if(machine!=0x8664)throw new ScanException("PE_MACHINE","目标不是x64引擎");if(count<1||count>96||optSize<112||optSize>4096)throw new ScanException("PE_TABLE_LAYOUT","PE节表布局不支持");
   var opt=HeaderRead(read,nt+24,optSize);ushort magic=BitConverter.ToUInt16(opt,0);if(magic!=0x20b)throw new ScanException("PE_OPTIONAL_MAGIC","目标不是PE32+格式");
   var image=new ImageInfo{Origin=origin,NtOffset=nt,Machine=machine,Magic=magic,OptionalSize=optSize,SizeOfImage=BitConverter.ToUInt32(opt,56),SizeOfHeaders=BitConverter.ToUInt32(opt,60),SectionAlignment=BitConverter.ToUInt32(opt,32)};
   if(observed!=null)observed(image);
   long table=nt+24+optSize;
   if(image.SizeOfImage==0||image.SizeOfImage>MaxImageSpan)throw new ScanException("PE_IMAGE_BUDGET","映像尺寸超过明确的1GiB地址跨度上限");
   if(image.SectionAlignment==0||image.SectionAlignment>1024*1024||(image.SectionAlignment&(image.SectionAlignment-1))!=0)throw new ScanException("PE_ALIGNMENT","PE节对齐值不合法");
   if(image.SizeOfHeaders<table+count*40||image.SizeOfHeaders>MaxHeaderBytes||image.SizeOfHeaders>image.SizeOfImage)throw new ScanException("PE_HEADERS_SIZE","PE头长度字段不合法");
   byte[] sections=HeaderRead(read,table,count*40);
   for(int i=0;i<count;i++){int off=i*40;var name=new StringBuilder();for(int j=0;j<8&&sections[off+j]!=0;j++){char c=(char)sections[off+j];name.Append(char.IsLetterOrDigit(c)||c=='.'||c=='_'||c=='-'?c:'?');}
    image.Sections.Add(new SectionInfo{Index=i,Name=name.ToString(),Rva=BitConverter.ToUInt32(sections,off+12),VirtualSize=BitConverter.ToUInt32(sections,off+8),RawSize=BitConverter.ToUInt32(sections,off+16),Flags=BitConverter.ToUInt32(sections,off+36)});
   }return image;
  }
  public static List<RvaRange> Plan(ImageInfo image,ScanDiagnostic report){
   var ranges=new List<RvaRange>();foreach(var s in image.Sections.Where(s=>s.Executable)){
    ulong len=s.Length;if(len==0){report.Warn("ZERO_EXECUTABLE_SECTION_SKIPPED");continue;}
    if((ulong)s.Rva<image.SizeOfHeaders||(ulong)s.Rva+len>image.SizeOfImage){report.Problem("SECTION_OUTSIDE_VERIFIED_IMAGE",s.Rva,(int)Math.Min(len,int.MaxValue));continue;}
    ranges.Add(new RvaRange{Start=s.Rva,Length=len,Discardable=s.Discardable});
   }
   var merged=new List<RvaRange>();foreach(var s in ranges.OrderBy(x=>x.Start)){
    if(merged.Count==0){merged.Add(s);continue;}var last=merged[merged.Count-1];
    if(s.Start<last.End||(s.Start==last.End&&last.Discardable==s.Discardable)){ulong end=Math.Max(last.End,s.End);if(s.Start<last.End)report.Warn("OVERLAPPING_SECTIONS_NORMALIZED");last.Length=end-last.Start;last.Discardable=last.Discardable&&s.Discardable;}
    else merged.Add(s);
   }
   report.PlannedExecutableBytes=checked((long)merged.Sum(x=>(decimal)x.Length));
   if(merged.Count==0)throw new ScanException("NO_VALID_EXECUTABLE_RANGE","没有合法的可执行节范围；可导出诊断查看实际节表");
   return merged;
  }
  public static bool Equivalent(ImageInfo a,ImageInfo b){if(a==null||b==null||a.SizeOfImage!=b.SizeOfImage||a.SizeOfHeaders!=b.SizeOfHeaders||a.Sections.Count!=b.Sections.Count)return false;return a.Sections.Zip(b.Sections,(x,y)=>x.Rva==y.Rva&&x.VirtualSize==y.VirtualSize&&x.RawSize==y.RawSize&&x.Flags==y.Flags).All(x=>x);}
 }
 public sealed class ImageScanSession {
  public const int DefaultChunkBytes=2*1024*1024;public const long DefaultReadBudget=512L*1024*1024;
  readonly IImagePageReader reader;readonly long module;readonly ImageInfo image;readonly ScanDiagnostic report;readonly int chunkSize,overlap;readonly long byteBudget;
  readonly List<RvaRange> accepted=new List<RvaRange>();
  public ImageScanSession(IImagePageReader reader,long module,ImageInfo image,ScanDiagnostic report,int chunkBytes=DefaultChunkBytes,int overlapBytes=64,long readBudget=DefaultReadBudget){
   if(module<0x10000||chunkBytes<128||chunkBytes>4*1024*1024||overlapBytes<0||overlapBytes>=chunkBytes||readBudget<1)throw new ArgumentException("Invalid scan bounds");
   this.reader=reader;this.module=module;this.image=image;this.report=report;chunkSize=chunkBytes;overlap=overlapBytes;byteBudget=readBudget;
  }
  public static bool Executable(uint protect){uint p=protect&0xff;return p==0x10||p==0x20||p==0x40||p==0x80;}
  public static bool Readable(uint protect){if((protect&0x100)!=0||(protect&0xff)==1)return false;uint p=protect&0xff;return p==2||p==4||p==8||p==0x20||p==0x40||p==0x80;}
  void Accept(ulong start,ulong length){if(accepted.Count>0&&accepted[accepted.Count-1].End==start)accepted[accepted.Count-1].Length+=length;else accepted.Add(new RvaRange{Start=start,Length=length});}
  public bool Contains(long address,int count){if(!report.Complete||count<1||address<module)return false;ulong start=(ulong)(address-module);return accepted.Any(r=>start>=r.Start&&start<r.End&&(ulong)count<=r.End-start);}
  public IEnumerable<CodeRegion> ReadCode(){
   accepted.Clear();report.Complete=false;report.Stage="PLAN_EXECUTABLE_RANGES";var ranges=PeImage.Plan(image,report);bool complete=report.FailureCount==0;byte[] tail=new byte[0];long previousEnd=0;var watch=Stopwatch.StartNew();
   report.Stage="QUERY_AND_READ_IMAGE_PAGES";
   foreach(var range in ranges){long cursor=checked(module+(long)range.Start),end=checked(module+(long)range.End);
    while(cursor<end){
     if(watch.Elapsed.TotalSeconds>90||report.PagesQueried>=65536)throw new ScanException("SCAN_TIME_OR_REGION_BUDGET","只读扫描达到时间/区域数量上限；不会放行写入");
     PageInfo page;
     try{page=reader.Query(cursor);}catch{report.Problem("VIRTUAL_QUERY_FAILED",cursor-module);throw new ScanException("VIRTUAL_QUERY_FAILED","无法读取目标映像页面属性");}
     if(page==null||page.Length==0||page.Address>cursor||page.Address<0||page.Length>(ulong)(long.MaxValue-page.Address))throw new ScanException("INVALID_MEMORY_REGION","系统返回的页面范围不合法");
     long pageEnd=page.Address+(long)page.Length;if(pageEnd<=cursor)throw new ScanException("NONADVANCING_MEMORY_REGION","页面枚举未向前推进");
     long next=Math.Min(end,pageEnd);ulong length=(ulong)(next-cursor);bool same=page.AllocationBase==module;string decision;
     if(!same||page.Type!=0x1000000){decision="NOT_THIS_IMAGE";complete=false;}
     else if(page.State!=0x1000){decision=range.Discardable?"DISCARDED_SECTION":"NOT_COMMITTED";if(!range.Discardable)complete=false;}
     else if(!Readable(page.Protect)){decision="UNREADABLE_EXECUTABLE_PAGE";complete=false;}
     else if(!Executable(page.Protect)){decision="NOT_CURRENTLY_EXECUTABLE";report.Warn("NONEXECUTABLE_MAPPING_SKIPPED");}
     else decision="READ_EXECUTABLE_IMAGE";
     report.Page(new PageNote{Rva=cursor-module,Length=length,State=page.State,Protect=page.Protect,Type=page.Type,SameAllocation=same,Decision=decision});
     if(decision!="READ_EXECUTABLE_IMAGE"){
      report.SkippedBytes+=checked((long)length);if(decision!="DISCARDED_SECTION"&&decision!="NOT_CURRENTLY_EXECUTABLE")report.Problem(decision,cursor-module,(int)Math.Min(length,(ulong)int.MaxValue));
      tail=new byte[0];previousEnd=0;cursor=next;continue;
     }
     while(cursor<next){int wanted=(int)Math.Min(chunkSize,next-cursor);if(report.ReadBytes+wanted>byteBudget)throw new ScanException("SCAN_BYTE_BUDGET","实际可读代码超过512MiB扫描预算；保留边界并拒绝写入");
      byte[] bytes=null;try{bytes=reader.Read(cursor,wanted);}catch{}if(bytes==null||bytes.Length!=wanted){complete=false;report.Problem("READ_EXECUTABLE_CHUNK_FAILED",cursor-module,wanted);tail=new byte[0];previousEnd=0;cursor+=wanted;continue;}
      report.ReadBytes+=wanted;report.ChunksRead++;Accept((ulong)(cursor-module),(ulong)wanted);
      if(previousEnd!=cursor)tail=new byte[0];byte[] joined;
      if(tail.Length==0)joined=bytes;else{joined=new byte[tail.Length+bytes.Length];Buffer.BlockCopy(tail,0,joined,0,tail.Length);Buffer.BlockCopy(bytes,0,joined,tail.Length,bytes.Length);}
      long start=cursor-tail.Length;int keep=Math.Min(overlap,joined.Length);tail=new byte[keep];if(keep>0)Buffer.BlockCopy(joined,joined.Length-keep,tail,0,keep);cursor+=wanted;previousEnd=cursor;
      yield return new CodeRegion{Address=start,Bytes=joined};
     }
    }
   }
   if(report.ReadBytes==0){report.Problem("NO_READABLE_EXECUTABLE_CODE");throw new ScanException("NO_READABLE_EXECUTABLE_CODE","未读到该引擎映像的可读代码页，可导出诊断");}
   report.Complete=complete&&report.FailureCount==0;report.Stage="CODE_SCAN_FINISHED";report.Outcome=report.Complete?"COMPLETE_READONLY_SNAPSHOT":"INCOMPLETE_READONLY_SNAPSHOT";
  }
 }
}
