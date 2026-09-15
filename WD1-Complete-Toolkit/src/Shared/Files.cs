// Original WD1 Toolkit code. MIT license. No game memory access or network requests.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Diagnostics;

namespace WD1Kit {
    public static class Files {
        public static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 };
        public static string Hash(string path) { using(var f=File.OpenRead(path)) using(var h=SHA256.Create()) return BitConverter.ToString(h.ComputeHash(f)).Replace("-", ""); }
        public static T Read<T>(string path) { if(new FileInfo(path).Length>8*1024*1024) throw new IOException("JSON 文件过大。"); return Json.Deserialize<T>(File.ReadAllText(path,Encoding.UTF8)); }
        public static void Write(string path, object data) { AtomicText(path,Json.Serialize(data)); }
        public static void AtomicText(string path,string text) {
            NoLinks(Path.GetFullPath(path));
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string temp=path+".tmp-"+Guid.NewGuid().ToString("N");
            File.WriteAllText(temp,text,new UTF8Encoding(false));
            try { if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path); }
            finally { if(File.Exists(temp)) File.Delete(temp); }
        }
        public static string Full(string p) { string a=Path.GetFullPath(p), r=Path.GetPathRoot(a); return a.Length>r.Length?a.TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar):a; }
        public static bool Same(string a,string b) { return string.Equals(Full(a),Full(b),StringComparison.OrdinalIgnoreCase); }
        public static bool Under(string path,string root) { return Full(path).StartsWith(Full(root).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase); }
        public static void NoLinks(string path) {
            string p=Path.GetFullPath(path);
            while(!string.IsNullOrEmpty(p)) {
                if((File.Exists(p)||Directory.Exists(p)) && (File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0) throw new IOException("拒绝符号链接 / 目录联接路径。");
                var parent=Directory.GetParent(p); if(parent==null) break; p=parent.FullName;
            }
        }
        public static void Leaf(string name) {
            if(string.IsNullOrWhiteSpace(name)||name=="."||name==".."||name.IndexOfAny(new[]{'/','\\',':','\0'})>=0||name!=name.Trim()||name.EndsWith(".")) throw new IOException("不安全的文件名。");
        }
        public static void CopyFile(string src,string dest) {
            NoLinks(src); NoLinks(Path.GetDirectoryName(dest));
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            File.Copy(src,dest,false);
            if(Hash(src)!=Hash(dest)) throw new IOException("复制后 SHA-256 校验失败。");
        }
        public static void CopyTree(string src,string dest) {
            NoLinks(src); NoLinks(dest);
            if(Same(src,dest)||Under(dest,src)||Under(src,dest)) throw new IOException("源目录与目标目录不可嵌套。");
            int files=0; long bytes=0;
            Action<string,string,int> copy=null;
            copy=(s,d,depth)=>{
                if(depth>12) throw new IOException("目录层级异常。"); NoLinks(s); NoLinks(d); Directory.CreateDirectory(d);
                foreach(var f in Directory.GetFiles(s)) { NoLinks(f); if(++files>256||(bytes+=new FileInfo(f).Length)>32*1024*1024) throw new IOException("插件目录超出安全大小限制。"); CopyFile(f,Path.Combine(d,Path.GetFileName(f))); }
                foreach(var dir in Directory.GetDirectories(s)) copy(dir,Path.Combine(d,Path.GetFileName(dir)),depth+1);
            }; copy(src,dest,0);
        }
        public static bool Running(string name) { try { return Process.GetProcessesByName(name).Any(); } catch { return true; } }
        public static void GameClosed() { if(Running("Watch_Dogs")) throw new IOException("请正常保存并完全退出 Watch_Dogs，再执行此操作。工具不会结束游戏进程。"); }
        public static void CloudClosed() { GameClosed(); if(Running("UbisoftConnect")||Running("upc")||Running("Uplay")||Running("UbisoftGameLauncher")) throw new IOException("恢复存档前，请完全退出 Ubisoft Connect，避免云存档覆盖。不会自动结束进程。"); }
    }
    public sealed class GameCheck { public bool Matches; public Dictionary<string,string> Hashes=new Dictionary<string,string>(); public List<string> Problems=new List<string>(); public string Root; }
    public static class Identity {
        public const string ExeHash="844E4A85FD1D1AFE61BE2B75F451FA4A1BE91C83732731CC5ED2C36FF551E0CD";
        public const string EngineHash="A4EEAD7A645AB4340A67622DA4BFC91789E8CECFD53F605499A0E4B09B3EE60A";
        public const string LoaderHash="4325FFDE93C453F68E5B13CFD225D90359FCF73331C65F23894128CEA6DCD116";
        public static readonly string[] Modules={"wd1kit_campaign","wd1kit_dlc_solo"};
        public static GameCheck Check(string root) {
            var r=new GameCheck {Root=Files.Full(root)}; Files.NoLinks(root);
            var expected=new Dictionary<string,string>{{"Watch_Dogs.exe",ExeHash},{"Disrupt_b64.dll",EngineHash},{"uplay_r1_loader64.dll",LoaderHash}};
            if(!Directory.Exists(Path.Combine(root,"data_win64"))) r.Problems.Add("没有找到 data_win64；请选择游戏根目录，而不是 bin。");
            foreach(var pair in expected) {
                var f=Path.Combine(root,"bin",pair.Key);
                if(!File.Exists(f)) {r.Problems.Add("缺少 "+pair.Key);continue;}
                Files.NoLinks(f); r.Hashes[pair.Key]=Files.Hash(f);
                if(r.Hashes[pair.Key]!=pair.Value) r.Problems.Add(pair.Key+" 与用户报告指纹不同，拒绝安装 / 启动测试。");
            }
            r.Matches=r.Problems.Count==0; return r;
        }
        public static void Require(string root) { var r=Check(root); if(!r.Matches) throw new IOException(string.Join("\n",r.Problems)); }
    }
    public class SaveFile { public string Name; public long Size; public string Sha256; }
    public class BackupManifest {
        public string Product="WD1KIT"; public int Format=1; public uint AppId=243470;
        public string Id; public string CreatedUtc; public string SourceDirectory; public string Kind;
        public List<SaveFile> Files=new List<SaveFile>();
    }
    public class BackupInfo { public string ManifestPath; public BackupManifest Manifest; }
    public sealed class LocalStorage {
        public readonly string Root;
        public LocalStorage(string root) {Root=Files.Full(root); Files.NoLinks(Root); Directory.CreateDirectory(Root);}
        public static bool IsSave(string name) { return Regex.IsMatch(name,@"^[^/\\:]+\.(?:save(?:\.[a-zA-Z0-9_-]+)*|sav)$",RegexOptions.IgnoreCase); }
        public List<string> SaveFiles(string dir,bool allowEmpty=false) {
            Files.NoLinks(dir); if(!Directory.Exists(dir)||Directory.GetParent(Files.Full(dir))==null) throw new IOException("请选择实际存档文件所在的文件夹。");
            if(Files.Same(dir,Root)||Files.Under(Root,dir)||Files.Under(dir,Root)) throw new IOException("不能把工具备份目录当作游戏存档目录。");
            var list=Directory.GetFiles(dir).Where(f=>IsSave(Path.GetFileName(f))).OrderBy(f=>f,StringComparer.OrdinalIgnoreCase).ToList();
            if((list.Count==0&&!allowEmpty)||list.Count>128) throw new IOException("未找到 .save / .sav 文件，或文件数异常；请不要选游戏目录、账号父目录或 GamerProfile.xml。");
            long total=0; foreach(var f in list) {Files.NoLinks(f); total+=new FileInfo(f).Length;}
            if(total>32*1024*1024) throw new IOException("存档文件总量超过 32 MB 安全上限，请先核实目录。");
            return list;
        }
        public BackupInfo Backup(string source,string kind="manual") {
            Files.GameClosed(); var files=SaveFiles(source);
            var m=new BackupManifest {Id=DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N").Substring(0,8),CreatedUtc=DateTime.UtcNow.ToString("o"),SourceDirectory=Files.Full(source),Kind=kind};
            var parent=Path.Combine(Root,"backups"); Directory.CreateDirectory(parent);
            var stage=Path.Combine(parent,".pending-"+m.Id); var final=Path.Combine(parent,m.Id); Directory.CreateDirectory(stage);
            try {
                foreach(var src in files) {string name=Path.GetFileName(src); Files.Leaf(name); string dest=Path.Combine(stage,"files",name); Files.CopyFile(src,dest); m.Files.Add(new SaveFile{Name=name,Size=new FileInfo(dest).Length,Sha256=Files.Hash(dest)});}
                // Verify that no save was added/removed/changed during the snapshot.
                var after=SaveFiles(source);
                if(!after.Select(Path.GetFileName).SequenceEqual(m.Files.Select(f=>f.Name),StringComparer.OrdinalIgnoreCase)) throw new IOException("备份期间存档列表改变，请完全退出游戏 / 云客户端后重试。");
                foreach(var f in m.Files) if(Files.Hash(Path.Combine(source,f.Name))!=f.Sha256) throw new IOException("备份期间存档发生变化。");
                Files.Write(Path.Combine(stage,"backup.json"),m); Directory.Move(stage,final);
                return Verify(Path.Combine(final,"backup.json"));
            } catch {if(Directory.Exists(stage)) Directory.Delete(stage,true); throw;}
        }
        public BackupInfo Verify(string path) {
            Files.NoLinks(path); var marker=Files.Read<Dictionary<string,object>>(path);
            if(marker==null||!marker.ContainsKey("Product")||!marker.ContainsKey("Format")||!marker.ContainsKey("AppId")) throw new IOException("备份缺少明确的产品 / 格式标记。");
            var m=Files.Read<BackupManifest>(path);
            if(m==null||m.Product!="WD1KIT"||m.Format!=1||m.AppId!=243470||m.Files==null||m.Files.Count<1||m.Files.Count>128||!Regex.IsMatch(m.Id??"",@"^\d{8}-\d{6}-[0-9a-f]{8}$")) throw new IOException("不是本工具支持的 WD1 备份。");
            DateTime created; if(!DateTime.TryParse(m.CreatedUtc,null,System.Globalization.DateTimeStyles.RoundtripKind,out created)) throw new IOException("备份时间无效。");
            var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase); long size=0;
            foreach(var f in m.Files) {
                Files.Leaf(f.Name); if(!IsSave(f.Name)||!names.Add(f.Name)||f.Size<0||(size+=f.Size)>32*1024*1024||!Regex.IsMatch(f.Sha256??"",@"^[0-9A-Fa-f]{64}$")) throw new IOException("备份清单包含无效文件。");
                string src=Path.Combine(Path.GetDirectoryName(path),"files",f.Name); Files.NoLinks(src);
                if(!File.Exists(src)||new FileInfo(src).Length!=f.Size||!string.Equals(Files.Hash(src),f.Sha256,StringComparison.OrdinalIgnoreCase)) throw new IOException("备份文件损坏或缺失："+f.Name);
            }
            if(string.IsNullOrWhiteSpace(m.SourceDirectory)||!Path.IsPathRooted(m.SourceDirectory)||Directory.GetParent(Files.Full(m.SourceDirectory))==null) throw new IOException("备份原始目录无效。");
            return new BackupInfo{ManifestPath=Files.Full(path),Manifest=m};
        }
        public void Restore(string manifestPath,string selectedSaveDirectory,Action<int> fault=null) {
            Files.CloudClosed(); var b=Verify(manifestPath); var dir=Files.Full(selectedSaveDirectory);
            if(!Files.Same(dir,b.Manifest.SourceDirectory)) throw new IOException("恢复目标必须与此备份记录的原始目录一致；不会跨账号 / 跨目录覆盖。");
            var old=SaveFiles(dir,true); foreach(var f in old) if((File.GetAttributes(f)&FileAttributes.ReadOnly)!=0) throw new IOException("目标存档为只读，拒绝恢复；请先核实权限，不会自动更改属性。"); BackupInfo rollback=old.Count>0?Backup(dir,"before-restore"):null;
            var written=new List<string>();
            try {
                int i=0; foreach(var f in b.Manifest.Files) {if(fault!=null)fault(i++); var dest=Path.Combine(dir,f.Name); written.Add(dest); File.Copy(Path.Combine(Path.GetDirectoryName(manifestPath),"files",f.Name),dest,true); if(Files.Hash(dest)!=f.Sha256) throw new IOException("恢复后校验失败。");}
                var keep=new HashSet<string>(b.Manifest.Files.Select(f=>f.Name),StringComparer.OrdinalIgnoreCase);
                foreach(var f in old) if(!keep.Contains(Path.GetFileName(f))) File.Delete(f);
            } catch {
                foreach(var f in written) if(File.Exists(f)) File.Delete(f);
                if(rollback!=null) foreach(var f in rollback.Manifest.Files) File.Copy(Path.Combine(Path.GetDirectoryName(rollback.ManifestPath),"files",f.Name),Path.Combine(dir,f.Name),true);
                throw;
            }
        }
        public string Receipt(BackupInfo b,string mode) {
            b=Verify(b.ManifestPath); var created=DateTime.Parse(b.Manifest.CreatedUtc,null,System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime();
            if(created>DateTime.UtcNow.AddMinutes(1)||DateTime.UtcNow-created>TimeSpan.FromHours(2)) throw new IOException("备份超过两小时，请退出游戏后重新备份再授权。");
            long unix=(long)(created-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalSeconds;
            return "-- Locally issued backup receipt, not a cryptographic signature.\nreturn {format=1,product=\"WD1KIT\",mode=\""+mode+"\",allow_persistent=true,backup_id=\""+b.Manifest.Id+"\",created_unix="+unix+",expires_unix="+(unix+7200)+"}\n";
        }
        bool Owned(string dir,string module) {
            if(!Directory.Exists(dir)) return false; Files.NoLinks(dir);
            string f=Path.Combine(dir,"toolkit-owner.json"); if(!File.Exists(f)) throw new IOException("同名插件目录不属于本工具，拒绝覆盖。");
            var m=Files.Read<Dictionary<string,object>>(f);
            if(!m.ContainsKey("Product")||!m.ContainsKey("Module")||(string)m["Product"]!="WD1KIT"||(string)m["Module"]!=module) throw new IOException("插件归属标记不符，拒绝操作。"); return true;
        }
        public void Install(string game,string payload,BackupInfo backup,bool hostConfirmed,Action<int> fault=null) {
            Files.GameClosed();
#if !WD1KIT_FIXTURES
            Identity.Require(game);
#endif
            Files.NoLinks(game); Files.NoLinks(payload);
            if(!hostConfirmed) throw new IOException("请先按作者说明安装 NexusTools >=1.1.12，并确认看见宿主配置窗口。");
            if(backup!=null) {backup=Verify(backup.ManifestPath); if(!SaveFiles(backup.Manifest.SourceDirectory).Select(Path.GetFileName).SequenceEqual(backup.Manifest.Files.Select(f=>f.Name),StringComparer.OrdinalIgnoreCase)) throw new IOException("存档列表与备份不一致，请重新备份。"); foreach(var f in backup.Manifest.Files) if(!File.Exists(Path.Combine(backup.Manifest.SourceDirectory,f.Name))||Files.Hash(Path.Combine(backup.Manifest.SourceDirectory,f.Name))!=f.Sha256) throw new IOException("存档与备份不一致，请重新备份。");}
            string id=Guid.NewGuid().ToString("N"), stage=Path.Combine(game,"data_win64",".wd1kit-stage-"+id), mods=Path.Combine(game,"data_win64","mods"), rollback=Path.Combine(Root,"plugin-rollback",id);
            Files.NoLinks(mods); Directory.CreateDirectory(mods); Directory.CreateDirectory(stage);
            var old=new HashSet<string>();
            try {
                foreach(var module in Identity.Modules) {
                    string src=Path.Combine(payload,module), dest=Path.Combine(mods,module);
                    if(!Owned(src,module)) throw new IOException("发行包缺少插件。");
                    Files.CopyTree(src,Path.Combine(stage,module));
                    string mode=module=="wd1kit_campaign"?"campaign":"dlc_solo";
                    if(backup!=null) Files.AtomicText(Path.Combine(stage,module,"workspace",module,"receipt.lua"),Receipt(backup,mode));
                    if(Owned(dest,module)) {Files.CopyTree(dest,Path.Combine(rollback,module));old.Add(module);}
                }
                try {
                    int n=0; foreach(var module in Identity.Modules) {
                        if(fault!=null) fault(n++);
                        string dest=Path.Combine(mods,module);
                        if(Directory.Exists(dest)) Directory.Delete(dest,true);
                        Directory.Move(Path.Combine(stage,module),dest);
                    }
                } catch {
                    foreach(var module in Identity.Modules) {
                        string dest=Path.Combine(mods,module);
                        if(Directory.Exists(dest) && Owned(dest,module)) Directory.Delete(dest,true);
                        if(old.Contains(module)) Files.CopyTree(Path.Combine(rollback,module),dest);
                    }
                    throw;
                }
            } finally {if(Directory.Exists(stage)) Directory.Delete(stage,true);}
        }
        public void RevokeReceipts(string game) {
            Files.GameClosed(); Files.NoLinks(game);
            foreach(var module in Identity.Modules) {
                string dir=Path.Combine(game,"data_win64","mods",module);
                if(Owned(dir,module)) Files.AtomicText(Path.Combine(dir,"workspace",module,"receipt.lua"),"-- Revoked by companion.\nreturn {allow_persistent=false}\n");
            }
        }
        public void Uninstall(string game) {
            Files.GameClosed(); Files.NoLinks(game);
            string archive=Path.Combine(Root,"removed-plugins",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N").Substring(0,8));
            var dirs=new List<string>();
            foreach(var module in Identity.Modules) {string dir=Path.Combine(game,"data_win64","mods",module); if(Owned(dir,module)) {Files.CopyTree(dir,Path.Combine(archive,module));dirs.Add(dir);}}
            foreach(var dir in dirs) Directory.Delete(dir,true);
        }
    }
}
