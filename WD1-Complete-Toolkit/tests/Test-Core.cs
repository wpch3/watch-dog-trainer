using System;using System.IO;using System.Linq;using System.Collections.Generic;using WD1Kit;
namespace WD1Kit.Tests {class Runner {
static int count;static void Check(bool b,string n){if(!b)throw new Exception("FAIL "+n);Console.WriteLine("PASS "+n);count++;}
static void Fails(Action a,string n){bool b=false;try{a();}catch{b=true;}Check(b,n);}
static void Put(string f,string text){Directory.CreateDirectory(Path.GetDirectoryName(f));File.WriteAllText(f,text);}
static int Main(string[] args){string project=Path.GetFullPath(args.Length>0?args[0]:Directory.GetCurrentDirectory());string root=Path.Combine(Path.GetTempPath(),"WD1KIT-fixture-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);try{
                string source=Path.Combine(root,"saves"),data=Path.Combine(root,"tool-data");
                Put(Path.Combine(source,"1.save"),"abc");Put(Path.Combine(source,"2.save"),"def");Put(Path.Combine(source,"1.save.upload"),"metadata");Put(Path.Combine(source,"unrelated.txt"),"KEEP");
                var store=new LocalStorage(data);
                Check(Files.Hash(Path.Combine(source,"1.save"))=="BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD","SHA-256 known vector");
                Check(store.SaveFiles(source).Count==3,"recognized saves and upload sidecar only");
                Check(!LocalStorage.IsSave("GamerProfile.xml"),"profile is not a save");
                Check(!LocalStorage.IsSave("Disrupt_b64.dll"),"DLL is not a save");
                Fails(()=>store.SaveFiles(root),"empty candidate is not a backup");
                Fails(()=>store.SaveFiles(data),"cannot back up own storage recursively");
                Fails(()=>Files.Leaf("../escape.save"),"path traversal rejected");Fails(()=>Files.Leaf("C:escape.save"),"alternate data stream / drive prefix rejected");
                Fails(()=>Files.Leaf("nested\\1.save"),"backslash traversal rejected");
                Check(Files.Full(Path.GetPathRoot(root))==Path.GetPathRoot(root),"path root preserved");
                var b=store.Backup(source);Check(b.Manifest.Files.Count==3,"backup snapshots exact list");
                Check(File.ReadAllText(Path.Combine(source,"1.save"))=="abc","backup leaves originals unchanged");
                Check(store.Verify(b.ManifestPath).Manifest.AppId==243470,"backup identity and hashes validated");
                string originalManifest=File.ReadAllText(b.ManifestPath);var marker=Files.Read<Dictionary<string,object>>(b.ManifestPath);marker.Remove("Product");Files.Write(b.ManifestPath,marker);Fails(()=>store.Verify(b.ManifestPath),"missing explicit backup product marker rejected");File.WriteAllText(b.ManifestPath,originalManifest);
                string receipt=store.Receipt(b,"campaign");Check(receipt.Contains("allow_persistent=true"),"verified backup authorizes receipt");Check(!receipt.Contains(source),"receipt contains no private save path");
                string backup1=Path.Combine(Path.GetDirectoryName(b.ManifestPath),"files","1.save");File.WriteAllText(backup1,"CORRUPT");Fails(()=>store.Verify(b.ManifestPath),"corrupted backup rejected");File.WriteAllText(backup1,"abc");
                b.Manifest.CreatedUtc=DateTime.UtcNow.AddHours(-3).ToString("o");Files.Write(b.ManifestPath,b.Manifest);Fails(()=>store.Receipt(b,"campaign"),"old backup cannot mint fresh receipt");
                b=store.Backup(source);
                string wrong=Path.Combine(root,"other-saves");Put(Path.Combine(wrong,"1.save"),"OTHER");Fails(()=>store.Restore(b.ManifestPath,wrong),"cross-directory restore rejected");
                File.WriteAllText(Path.Combine(source,"1.save"),"new-1");File.WriteAllText(Path.Combine(source,"2.save"),"new-2");Put(Path.Combine(source,"3.save"),"new-slot");
                File.SetAttributes(Path.Combine(source,"1.save"),FileAttributes.ReadOnly);Fails(()=>store.Restore(b.ManifestPath,source),"read-only destination refused before restore writes");Check(File.ReadAllText(Path.Combine(source,"2.save"))=="new-2","read-only preflight leaves other files unchanged");File.SetAttributes(Path.Combine(source,"1.save"),FileAttributes.Normal);
                Fails(()=>store.Restore(b.ManifestPath,source,n=>{if(n==1)throw new IOException("fixture failure");}),"injected restore failure returns error");
                Check(File.ReadAllText(Path.Combine(source,"1.save"))=="new-1"&&File.ReadAllText(Path.Combine(source,"2.save"))=="new-2","partial restore rolled back");
                Check(File.Exists(Path.Combine(source,"3.save")),"rollback preserves extra slot");
                store.Restore(b.ManifestPath,source);Check(File.ReadAllText(Path.Combine(source,"1.save"))=="abc","restore succeeds");
                Check(!File.Exists(Path.Combine(source,"3.save")),"extra recognized slot removed only after backup");Check(File.ReadAllText(Path.Combine(source,"unrelated.txt"))=="KEEP","unrelated files untouched");
                Check(Directory.GetDirectories(Path.Combine(data,"backups")).Length>=4,"pre-restore snapshots retained");
                string game=Path.Combine(root,"fixture-game");Directory.CreateDirectory(Path.Combine(game,"data_win64"));Put(Path.Combine(game,"bin","Watch_Dogs.exe"),"FIXTURE EXE");Put(Path.Combine(game,"bin","Disrupt_b64.dll"),"FIXTURE DLL");Put(Path.Combine(game,"bin","uplay_r1_loader64.dll"),"FIXTURE LOADER");
                Check(!Identity.Check(game).Matches,"unknown real binary hashes rejected");Fails(()=>Identity.Require(game),"identity fail closed");
                string payload=Path.Combine(project,"payload");
                Fails(()=>store.Install(game,payload,null,false),"host not confirmed rejects fixture installation");
                store.Install(game,payload,null,true);string installed=Path.Combine(game,"data_win64","mods","wd1kit_campaign");
                Check(File.Exists(Path.Combine(installed,"modconfig.json")),"temporary plugin installed");
                string installedReceipt=Path.Combine(installed,"workspace","wd1kit_campaign","receipt.lua");Check(File.ReadAllText(installedReceipt).Contains("allow_persistent=false"),"temporary install has no persistent permission");
                Put(Path.Combine(installed,"my-custom-note.txt"),"PRESERVE USER EDIT");
                Fails(()=>store.Install(game,payload,null,true,n=>{if(n==1)throw new IOException("fixture swap failure");}),"two-module swap failure detected");
                Check(File.ReadAllText(Path.Combine(installed,"my-custom-note.txt"))=="PRESERVE USER EDIT","failed update restores old custom files");
                Check(File.Exists(Path.Combine(game,"data_win64","mods","wd1kit_dlc_solo","modconfig.json")),"second module restored after transaction failure");
                b=store.Backup(source);store.Install(game,payload,b,true);Check(File.ReadAllText(installedReceipt).Contains("allow_persistent=true"),"persistent install gets validated receipt");
                Put(Path.Combine(source,"new.save"),"new");Fails(()=>store.Install(game,payload,b,true),"new unbacked save file blocks installation");File.Delete(Path.Combine(source,"new.save"));
                File.WriteAllText(Path.Combine(source,"1.save"),"changed");Fails(()=>store.Install(game,payload,b,true),"changed save blocks stale backup authorization");File.WriteAllText(Path.Combine(source,"1.save"),"abc");
                store.RevokeReceipts(game);Check(File.ReadAllText(installedReceipt).Contains("allow_persistent=false"),"restore workflow can revoke both plugin receipts");
                store.Uninstall(game);Check(!Directory.Exists(installed),"uninstall removes own plugin only");Check(File.ReadAllText(Path.Combine(game,"bin","Disrupt_b64.dll"))=="FIXTURE DLL","game binary untouched through install/update/uninstall");
                Put(Path.Combine(installed,"foreign.txt"),"FOREIGN");Fails(()=>store.Install(game,payload,null,true),"foreign same-name plugin refused");Check(File.ReadAllText(Path.Combine(installed,"foreign.txt"))=="FOREIGN","foreign directory untouched");
                string log=Path.Combine(root,"host.log");Put(log,"[host] ACCOUNT SECRET\n[time] [WD1KIT] CAP AddItem,GetSkillPointCount\n[WD1KIT] ERROR C:\\Users\\SECRET\\file\n[WD1KIT] PLUGIN_LOADED version=0.2.0-alpha mode=campaign game_runtime_verified=false\n[OTHER] credentials\n");
                var safe=WD1Kit.MainForm.ExtractLog(log);Check(safe.Count==2,"only restricted plugin lines exported");Check(!string.Join("\n",safe).Contains("SECRET"),"host log path/account strings excluded");

var assembly=System.Reflection.Assembly.LoadFile(Path.Combine(project,"WD1-Toolkit.exe"));var install=assembly.GetType("WD1Kit.LocalStorage").GetMethod("Install");var il=install.GetMethodBody().GetILAsByteArray();bool hasGuard=false;for(int i=0;i<il.Length-4;i++)if(il[i]==0x28)try{var method=install.Module.ResolveMethod(BitConverter.ToInt32(il,i+1));if(method.Name=="Require"&&method.DeclaringType.FullName=="WD1Kit.Identity")hasGuard=true;}catch{}Check(hasGuard,"actual release executable keeps version gate");
Console.WriteLine("CORE_FIXTURE_CHECKS="+count);NativeTests.Run();ImageScanTests.Run();CaptureTests.Run();return 0;
}catch(Exception ex){Console.Error.WriteLine(ex);return 1;}finally{if(Directory.Exists(root))Directory.Delete(root,true);}}
}}
