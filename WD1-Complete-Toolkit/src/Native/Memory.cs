// Original Windows-only process adapter. No driver, no network, no process termination.
using System;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
namespace WD1Kit.Native {
 public class CodeRegion {public long Address;public byte[] Bytes;}
 public class Change {public long Address;public byte[] Before,After;}
 public class SpanRange {public long Address;public int Length;}
 public interface IMemory:IDisposable {
  bool Alive {get;} IEnumerable<CodeRegion> Code();byte[] Read(long address,int count);void WriteData(long address,byte[] bytes);
  long AllocateNear(long address,int size);void Patch(IList<Change> changes,IList<SpanRange> extraProtected);long ModuleBase {get;}
 }
 public sealed class WinMemory:IMemory,IImagePageReader,IScanState {
  [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool ReadProcessMemory(IntPtr h,IntPtr at,byte[] data,UIntPtr count,out UIntPtr read);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool WriteProcessMemory(IntPtr h,IntPtr at,byte[] data,UIntPtr count,out UIntPtr written);
  [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr VirtualAllocEx(IntPtr h,IntPtr address,UIntPtr size,uint allocation,uint protection);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool VirtualProtectEx(IntPtr h,IntPtr address,UIntPtr size,uint newProtection,out uint oldProtection);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool FlushInstructionCache(IntPtr h,IntPtr address,UIntPtr size);
  [DllImport("kernel32.dll",SetLastError=true)]static extern IntPtr OpenThread(uint access,bool inherit,int tid);
  [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetThreadContext(IntPtr thread,IntPtr context);
  [DllImport("ntdll.dll")]static extern int NtSuspendProcess(IntPtr process);
  [DllImport("ntdll.dll")]static extern int NtResumeProcess(IntPtr process);
  [StructLayout(LayoutKind.Explicit,Size=48)]struct MEMORY_BASIC_INFORMATION64 {
   [FieldOffset(0)]public IntPtr BaseAddress;[FieldOffset(8)]public IntPtr AllocationBase;[FieldOffset(16)]public uint AllocationProtect;
   [FieldOffset(24)]public UIntPtr RegionSize;[FieldOffset(32)]public uint State;[FieldOffset(36)]public uint Protect;[FieldOffset(40)]public uint Type;
  }
  [DllImport("kernel32.dll",SetLastError=true)]static extern UIntPtr VirtualQueryEx(IntPtr process,IntPtr address,out MEMORY_BASIC_INFORMATION64 info,UIntPtr size);
  Process process;DateTime birth;IntPtr handle;bool writable,disposed;long module;int moduleSize;ImageInfo disk;ImageScanSession scanner;
  readonly ScanDiagnostic diagnostic;
  public long ModuleBase {get{return module;}}
  public bool ScanComplete {get{return diagnostic.Complete;}}
  public ScanDiagnostic Diagnostic {get{return diagnostic;}}
  public WinMemory(string game,ScanDiagnostic report=null) {
   diagnostic=report??new ScanDiagnostic();
   try {
    diagnostic.Stage="PLATFORM";
    if(Environment.OSVersion.Platform!=PlatformID.Win32NT||!Environment.Is64BitProcess)throw new ScanException("WINDOWS_X64_REQUIRED","原生连接需要64位Windows");
    diagnostic.Stage="FINGERPRINTS";Identity.Require(game);diagnostic.FingerprintsMatched=true;
    diagnostic.Stage="PROCESS";var matches=Process.GetProcessesByName("Watch_Dogs");
    if(matches.Length!=1){foreach(var match in matches)match.Dispose();throw new ScanException("ONE_GAME_PROCESS_REQUIRED","需要且只能有一个正在运行的Watch_Dogs进程");}
    process=matches[0];birth=process.StartTime.ToUniversalTime();
    if(!Files.Same(process.MainModule.FileName,Path.Combine(game,"bin","Watch_Dogs.exe")))throw new ScanException("PROCESS_PATH_MISMATCH","运行的游戏并非已校验的安装路径");
    diagnostic.ProcessPathMatched=true;diagnostic.Stage="ENGINE_MODULE";
    var dll=process.Modules.Cast<ProcessModule>().SingleOrDefault(m=>string.Equals(m.ModuleName,"Disrupt_b64.dll",StringComparison.OrdinalIgnoreCase));
    if(dll==null||!Files.Same(dll.FileName,Path.Combine(game,"bin","Disrupt_b64.dll")))throw new ScanException("ENGINE_PATH_MISMATCH","引擎模块路径不匹配");
    diagnostic.EnginePathMatched=true;module=dll.BaseAddress.ToInt64();moduleSize=dll.ModuleMemorySize;diagnostic.ReportedModuleBytes=moduleSize;
    handle=OpenProcess(0x410,false,process.Id);if(handle==IntPtr.Zero)throw new ScanException("OPEN_PROCESS_READ_FAILED","无法只读连接游戏，不会自动提权或关闭防护");
    diagnostic.Stage="VERIFIED_DISK_PE";
    using(var file=new FileStream(dll.FileName,FileMode.Open,FileAccess.Read,FileShare.Read)){
     disk=PeImage.Parse((offset,count)=>{if(offset<0||offset+count>file.Length)throw new ScanException("DISK_HEADER_BOUNDS","文件头范围不合法");file.Position=offset;var b=new byte[count];int done=0;while(done<count){int n=file.Read(b,done,count-done);if(n==0)throw new EndOfStreamException();done+=n;}return b;},"verified_disk",info=>diagnostic.Disk=info);
    }
    if(moduleSize<=0||moduleSize!=(long)disk.SizeOfImage)diagnostic.Warn("REPORTED_MODULE_SIZE_DIFFERS_FROM_DISK_IMAGE");
    diagnostic.Stage="RUNTIME_PE_DIAGNOSTIC";
    try{var runtime=PeImage.Parse((offset,count)=>Read(module+offset,count),"runtime_header",info=>diagnostic.Runtime=info);if(!PeImage.Equivalent(disk,runtime))diagnostic.Warn("RUNTIME_HEADERS_DIFFER_FROM_VERIFIED_DISK");}
    catch(ScanException ex){diagnostic.Warn("RUNTIME_HEADER_"+ex.Code);}catch{diagnostic.Warn("RUNTIME_HEADER_UNREADABLE");}
    diagnostic.Stage="READY_TO_SCAN";
   }catch(Exception ex){diagnostic.Failure(ex);Dispose();throw;}
  }
  public bool Alive {get{try{return !disposed&&!process.HasExited&&process.StartTime.ToUniversalTime()==birth;}catch{return false;}}}
  void RequireAlive(){if(!Alive)throw new IOException("游戏已退出或会话改变，请重新连接。");}
  void Upgrade(){RequireAlive();if(writable)return;var h=OpenProcess(0xc38,false,process.Id);if(h==IntPtr.Zero)throw new IOException("未获得本进程的内存操作权限，不会自动提权。");CloseHandle(handle);handle=h;writable=true;}
  public byte[] Read(long address,int count){RequireAlive();if(address<0x10000||count<1||count>64*1024*1024)throw new IOException("拒绝无效读取范围。");byte[] b=new byte[count];UIntPtr n;if(!ReadProcessMemory(handle,new IntPtr(address),b,(UIntPtr)count,out n)||n.ToUInt64()!=(ulong)count)throw new IOException("目标数据不可读或已失效。");return b;}
  public void WriteData(long address,byte[] bytes){Upgrade();if(address<0x10000||bytes.Length<1||bytes.Length>4096)throw new IOException("拒绝无效写入范围。");UIntPtr n;if(!WriteProcessMemory(handle,new IntPtr(address),bytes,(UIntPtr)bytes.Length,out n)||n.ToUInt64()!=(ulong)bytes.Length)throw new IOException("内存写入未完成。");if(!FlushInstructionCache(handle,new IntPtr(address),(UIntPtr)bytes.Length))throw new IOException("内存更新缓存刷新失败。");}
  public PageInfo Query(long address){
   RequireAlive();MEMORY_BASIC_INFORMATION64 m;var size=VirtualQueryEx(handle,new IntPtr(address),out m,(UIntPtr)48);
   if(size.ToUInt64()<48)throw new ScanException("VIRTUAL_QUERY_FAILED","无法读取映像页面属性");
   return new PageInfo{Address=m.BaseAddress.ToInt64(),AllocationBase=m.AllocationBase.ToInt64(),Length=m.RegionSize.ToUInt64(),State=m.State,Protect=m.Protect,Type=m.Type};
  }
  public IEnumerable<CodeRegion> Code(){
   RequireAlive();if(disk==null)throw new ScanException("DISK_HEADER_NOT_VALIDATED","尚未验证磁盘映像头");
   diagnostic.Complete=false;diagnostic.FailureCount=0;diagnostic.ReadBytes=0;diagnostic.SkippedBytes=0;diagnostic.PagesQueried=0;diagnostic.ChunksRead=0;diagnostic.ReadFailures.Clear();diagnostic.Pages.Clear();diagnostic.PageListTruncated=false;
   scanner=new ImageScanSession(this,module,disk,diagnostic);return scanner.ReadCode();
  }
  void RequireScannedCode(long address,int count){
   if(scanner==null||!scanner.Contains(address,count))throw new ScanException("PATCH_OUTSIDE_SCANNED_IMAGE","补丁不在完整扫描后确认的映像代码范围");
   var p=Query(address);if(p.Address>address||p.Length>(ulong)(long.MaxValue-p.Address)||p.Address+(long)p.Length<address+count||p.AllocationBase!=module||p.Type!=0x1000000||p.State!=0x1000||!ImageScanSession.Executable(p.Protect)||!ImageScanSession.Readable(p.Protect))throw new ScanException("PATCH_MAPPING_CHANGED","目标映像页面已变化或跨属性边界，拒绝改写");
  }
  public long AllocateNear(long address,int size){
   Upgrade();if(size!=4096)throw new IOException("只允许一页有界捕获缓冲区。");long pivot=address&~0xffffL;
   // Bounded search, ordinary VirtualAllocEx; allocations remain owned by the game until it exits.
   for(long distance=0x10000;distance<=0x70000000;distance+=0x10000){foreach(long at in new[]{pivot+distance,pivot-distance}){if(at<0x10000)continue;var p=VirtualAllocEx(handle,new IntPtr(at),(UIntPtr)size,0x3000,0x40);if(p!=IntPtr.Zero)return p.ToInt64();}}
   throw new IOException("无法在相对跳转范围内分配捕获缓冲，不安装跳转。");
  }
  List<long> InstructionPointers(){
   process.Refresh();var pointers=new List<long>();
   foreach(ProcessThread t in process.Threads){IntPtr h=OpenThread(0x48,false,t.Id);if(h==IntPtr.Zero)throw new IOException("无法检查线程位置，拒绝代码改写。");IntPtr allocation=Marshal.AllocHGlobal(1264);
    try{long aligned=(allocation.ToInt64()+15)&~15L;IntPtr context=new IntPtr(aligned);byte[] zero=new byte[1232];Marshal.Copy(zero,0,context,zero.Length);
     // Windows AMD64 CONTEXT_CONTROL: ContextFlags at +48; Rip at +248. These are ABI offsets, not game addresses.
     Marshal.WriteInt32(context,48,0x100001);if(!GetThreadContext(h,context))throw new IOException("线程上下文读取失败，拒绝代码改写。");pointers.Add(Marshal.ReadInt64(context,248));
    }finally{Marshal.FreeHGlobal(allocation);CloseHandle(h);}
   }return pointers;
  }
  public void Patch(IList<Change> changes,IList<SpanRange> extraProtected){
   if(changes.Count==0)return;Upgrade();
   foreach(var c in changes)if(c.Before.Length!=c.After.Length||c.Before.Length==0||c.Before.Length>32||c.Address<module)throw new IOException("补丁不在已核验的引擎范围。");
   foreach(var c in changes)RequireScannedCode(c.Address,c.Before.Length);
   bool suspended=false;var changed=new List<Change>();
   try{
    if(NtSuspendProcess(handle)!=0)throw new IOException("无法取得短暂安全写入窗口，不改变代码。");suspended=true;
    var ranges=changes.Select(c=>new SpanRange{Address=c.Address,Length=c.Before.Length}).Concat(extraProtected??new List<SpanRange>()).ToList();
    foreach(var rip in InstructionPointers())if(ranges.Any(r=>rip>=r.Address&&rip<r.Address+r.Length))throw new IOException("游戏线程正在目标指令/捕获段中；本次不更改，请稍后重试。");
    foreach(var c in changes){RequireScannedCode(c.Address,c.Before.Length);if(!Read(c.Address,c.Before.Length).SequenceEqual(c.Before))throw new IOException("代码已被其他模块修改，拒绝覆盖。");}
    foreach(var c in changes){changed.Add(c);WriteCode(c.Address,c.After);}
   }catch{
    bool rollbackFailed=false;foreach(var c in changed.AsEnumerable().Reverse())try{WriteCode(c.Address,c.Before);}catch{rollbackFailed=true;}
    if(rollbackFailed)throw new IOException("代码改写失败且回滚不完整：不要继续操作，彻底退出游戏后重新启动。");throw;
   }finally{if(suspended&&NtResumeProcess(handle)!=0)throw new IOException("恢复游戏运行的系统调用失败；停止操作并检查游戏状态。");}
  }
  void WriteCode(long address,byte[] bytes){uint old;if(!VirtualProtectEx(handle,new IntPtr(address),(UIntPtr)bytes.Length,0x40,out old))throw new IOException("无法修改目标页保护。");try{WriteData(address,bytes);if(!FlushInstructionCache(handle,new IntPtr(address),(UIntPtr)bytes.Length))throw new IOException("指令缓存刷新失败。");}finally{uint unused;if(!VirtualProtectEx(handle,new IntPtr(address),(UIntPtr)bytes.Length,old,out unused))throw new IOException("原页保护恢复失败。");}}
  public void Dispose(){if(disposed)return;disposed=true;if(handle!=IntPtr.Zero)CloseHandle(handle);if(process!=null)process.Dispose();}
 }
}
