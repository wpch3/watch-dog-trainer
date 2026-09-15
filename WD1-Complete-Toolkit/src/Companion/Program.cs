using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Drawing;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
[assembly:System.Reflection.AssemblyTitle("WD1 中文单机工具箱")]
[assembly:System.Reflection.AssemblyVersion("0.3.3.0")]
[assembly:System.Reflection.AssemblyFileVersion("0.3.3.0")]
namespace WD1Kit {
    class Settings {public string Game="";public string Save="";public string Backup="";}
    static class Program {
        [STAThread] static void Main(string[] args) {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            try {
                if(args.Contains("--native-ui-smoke")){
                    using(var f=new WD1Kit.Native.NativeForm("",new LocalStorage(Path.Combine(Path.GetTempPath(),"WD1KIT-native-ui-"+Guid.NewGuid().ToString("N"))),null)){
                        f.Shown+=(s,e)=>{var t=new Timer{Interval=900};t.Tick+=(a,b)=>{t.Stop();using(var bmp=new Bitmap(f.Width,f.Height)){using(var g=Graphics.FromImage(bmp))g.CopyFromScreen(f.Location,Point.Empty,f.Size);bmp.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ui-native.png"));}f.Close();};t.Start();};Application.Run(f);
                    }
                }else Application.Run(new MainForm(args.Contains("--ui-smoke")));
            }
            catch(Exception ex) {MessageBox.Show("无法启动："+ex.Message,"WD1 工具箱",MessageBoxButtons.OK,MessageBoxIcon.Error);}
        }
    }
    class MainForm:Form {
        LocalStorage store; Settings settings=new Settings(); BackupInfo backup; bool busy=false; readonly bool smoke;
        TextBox game=Theme.TextBox(),save=Theme.TextBox(),log=Theme.TextBox(true); Label status=Theme.Label("尚未校验。用户报告的指纹不是兼容性认证。");
        Label backupStatus=Theme.Label("未定位实际存档；不会把空列表当成已备份。");
        CheckBox host=new CheckBox {Text="我已从作者安装 NexusTools ≥ 1.1.12，并看到它的启动配置窗口",AutoSize=true,ForeColor=Theme.Text,Margin=new Padding(5,12,5,12)};
        CheckBox temporary=new CheckBox {Text="仅安装临时模式（无备份也可安装；弹药补给、现金、技能点、物品锁定）",AutoSize=true,ForeColor=Theme.Text,Margin=new Padding(5,8,5,8)};
        List<string> pluginLines=new List<string>();
        public MainForm(bool uiSmoke) {
            smoke=uiSmoke; Theme.Form(this,"WD1 中文单机工具箱 · 0.3.3 alpha · 未实机认证");
            string root=uiSmoke?Path.Combine(Path.GetTempPath(),"WD1KIT-ui-smoke-"+Guid.NewGuid().ToString("N")):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"WD1CompleteToolkit");
            store=new LocalStorage(root);
            if(!smoke) try {if(File.Exists(Path.Combine(root,"settings.json"))) settings=Files.Read<Settings>(Path.Combine(root,"settings.json"))??new Settings();}catch{}
            game.Text=settings.Game;save.Text=settings.Save;
            if(!smoke && !string.IsNullOrWhiteSpace(settings.Backup)) try {backup=store.Verify(settings.Backup);backupStatus.Text="已校验本地备份："+backup.Manifest.Id+" / "+backup.Manifest.Files.Count+" 文件（不是活动存档识别）。";}catch{}
            var tabs=new TabControl {Dock=DockStyle.Fill,Padding=new Point(20,9)};
            AddPage(tabs,"01  安装与启动",Setup()); AddPage(tabs,"02  存档与恢复",Saves()); AddPage(tabs,"03  游戏内参数",Features()); AddPage(tabs,"04  测试反馈",Reports());
            Controls.Add(tabs);Controls.Add(Theme.Header("0.3.3 ALPHA    ·    STEAM 243470 / 11241563    ·    编译完成 ≠ 游戏行为验证"));
            FormClosing+=(s,e)=>{if(busy){e.Cancel=true;MessageBox.Show("文件操作尚未结束，请等待完成。","WD1 工具箱");}else if(!smoke)SaveSettings();};
            if(smoke) Shown+=(s,e)=>{var timer=new Timer{Interval=900};timer.Tick+=(a,b)=>{timer.Stop(); using(var bmp=new Bitmap(Width,Height)){using(var gr=Graphics.FromImage(bmp)) gr.CopyFromScreen(Location,Point.Empty,Size);bmp.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ui-companion.png"));}Close();};timer.Start();};
        }
        void AddPage(TabControl tabs,string title,Control content) {var page=new TabPage(title){BackColor=Theme.Bg,ForeColor=Theme.Text,AutoScroll=true,Padding=new Padding(16)};page.Controls.Add(content);tabs.TabPages.Add(page);}
        void SaveSettings() {settings.Game=game.Text.Trim();settings.Save=save.Text.Trim();settings.Backup=backup==null?"":backup.ManifestPath;Files.Write(Path.Combine(store.Root,"settings.json"),settings);}
        void Note(string text){log.AppendText(DateTime.Now.ToString("HH:mm:ss")+"  "+text+Environment.NewLine);}
        async void Work(Func<string> fn,Action done=null) {
            if(busy){MessageBox.Show("请等待当前操作完成。");return;} busy=true;UseWaitCursor=true;
            try {string text=await Task.Run(fn);Note(text);if(done!=null)done();if(!smoke)SaveSettings();}
            catch(Exception ex){Note("操作停止："+ex.Message);MessageBox.Show(this,ex.Message,"操作未完成",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
            finally{busy=false;UseWaitCursor=false;}
        }
        bool Confirm(string text){return MessageBox.Show(this,text,"请确认",MessageBoxButtons.YesNo,MessageBoxIcon.Warning,MessageBoxDefaultButton.Button2)==DialogResult.Yes;}
        string Folder(string initial,string description) {using(var d=new FolderBrowserDialog{Description=description,SelectedPath=Directory.Exists(initial)?initial:"",ShowNewFolderButton=false})return d.ShowDialog(this)==DialogResult.OK?d.SelectedPath:null;}
        void Open(string path){try{Process.Start(new ProcessStartInfo(path){UseShellExecute=true});}catch(Exception ex){MessageBox.Show(ex.Message);}}
        Control Setup() {
            var p=Theme.Flow(true);p.Controls.Add(Theme.Label("先匹配版本，再安装自己的插件",true));
            p.Controls.Add(Theme.Label("安装器不覆盖原版 EXE / DLL / dat / fat；原生控制会临时修改进程指令/数值。请将整包解压到游戏目录之外。"));
            p.Controls.Add(Theme.Label("游戏根目录（含 bin 和 data_win64）"));p.Controls.Add(game);
            var row=Theme.Flow();row.Controls.Add(Theme.Button("选择游戏目录",(s,e)=>{var x=Folder(game.Text,"选择 Watch Dogs 1 根目录");if(x!=null){game.Text=x;Check();}}));
            row.Controls.Add(Theme.Button("从 Steam 定位",(s,e)=>{var list=FindGames();if(list.Count==1){game.Text=list[0];Check();}else Choose(list,"请选择 WD1 安装目录",x=>{game.Text=x;Check();});}));row.Controls.Add(Theme.Button("校验三项 SHA-256",(s,e)=>Check()));p.Controls.Add(row);p.Controls.Add(status);
            p.Controls.Add(Theme.Button("打开宿主作者安装说明",(s,e)=>Open("https://www.kaverti.com/en/TroploNexusTools/Home")));
            p.Controls.Add(host);p.Controls.Add(temporary);
            p.Controls.Add(Theme.Label("完整物品测试：到“存档与恢复”选择实际 .save 文件夹并备份，再回来安装。备份授权只持续两小时，过期后需退出游戏、重新备份并再次安装。"));
            var actions=Theme.Flow();actions.Controls.Add(Theme.Button("安装 / 更新游戏插件",(s,e)=>Install(),true));
            actions.Controls.Add(Theme.Button("校验后启动 Steam 游戏",(s,e)=>{
                string g=game.Text.Trim(); if(!host.Checked){MessageBox.Show("请先安装并确认宿主。");return;}
                Work(()=>{Files.GameClosed();Identity.Require(g);return "启动前指纹校验通过；尚不代表宿主兼容性已验证。";},()=>Open("steam://rungameid/243470"));
            }));actions.Controls.Add(Theme.Button("卸载本工具插件",(s,e)=>{string g=game.Text.Trim();if(!Confirm("只移除 wd1kit_campaign / wd1kit_dlc_solo，先归档副本。\n不会卸载 NexusTools，也不会撤销已保存的物品。"))return;Work(()=>{store.Uninstall(g);return "本工具插件已移出游戏目录；原文件归档在本地工具数据目录。";});}));p.Controls.Add(actions);
            p.Controls.Add(Theme.Label("游戏内：按 Insert / Pause / Ctrl+\\ 打开宿主 → WD1 KIT → ARM。默认所有持续效果关闭；物品先“准备”再 CONFIRM。本体与 Bad Blood 切换时请完全退出游戏重启。"));return p;
        }
        void Check(){string g=game.Text.Trim();GameCheck result=null;Work(()=>{result=Identity.Check(g);return result.Matches?"三项指纹与报告一致。游戏修改仍未实机认证。":string.Join(" / ",result.Problems);},()=>{status.Text=result.Matches?"匹配用户观察目标：11241563 · 安装校验通过 · 运行兼容性待测":string.Join("\n",result.Problems);status.ForeColor=result.Matches?Theme.Accent:Color.Salmon;});}
        void Install() {
            string g=game.Text.Trim();bool h=host.Checked,t=temporary.Checked;var b=backup;
            if(!t && b==null){MessageBox.Show("请先选择并备份真实存档；或明确选择“仅安装临时模式”。");return;}
            if(!t&&!Files.Same(save.Text.Trim(),b.Manifest.SourceDirectory)){MessageBox.Show("当前选择的存档目录与备份不一致，请重新备份。");return;}
            if(!Confirm(t?"安装临时模式：弹药补给、物品、金钱、技能点奖励锁定。\n插件和宿主在你的构建上还没有实际游戏测试。继续？":"确认这份备份属于你接下来加载的账号 / 存档。\n在单机自由探索测试；不要进入联机内容。\n这会写入两个工具插件目录，但不会修改原版资源文件。继续？"))return;
            Work(()=>{store.Install(g,Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"payload"),t?null:b,h);return t?"临时模式插件已安装。持久写入仍被锁定。":"插件已安装，备份回执有效期截至 "+DateTime.Parse(b.Manifest.CreatedUtc).ToLocalTime().AddHours(2).ToString("HH:mm")+"。";});
        }
        Control Saves() {
            var p=Theme.Flow(true);p.Controls.Add(Theme.Label("先找对存档，再做一份可校验副本",true));
            p.Controls.Add(Theme.Label("你的检测报告没有找到存档。下面的定位只列候选，不自动认定活动账号。Steam 版通常是 Ubisoft Connect\\savegames\\账号\\541；不是 GamerProfile.xml。"));p.Controls.Add(save);
            var row=Theme.Flow();row.Controls.Add(Theme.Button("查找候选存档",(s,e)=>Choose(FindSaves(),"选择你的 WD1 存档目录（不要选择别的账号）",x=>{save.Text=x;backup=null;backupStatus.Text="新选择的目录尚未备份。";})));
            row.Controls.Add(Theme.Button("手动选择存档目录",(s,e)=>{var x=Folder(save.Text,"选含 .save / .sav 文件的 WD1 存档目录");if(x!=null){save.Text=x;backup=null;backupStatus.Text="新选择的目录尚未备份。";}}));
            row.Controls.Add(Theme.Button("校验并备份",(s,e)=>{string dir=save.Text.Trim();if(!Confirm("请确认这个文件夹确实属于你的 WD1 存档，且本体 / Bad Blood 档案都已包含。\n先正常保存并退出游戏。不会上传任何文件。\n"+dir))return;Work(()=>{backup=store.Backup(dir);return "备份完成，逐文件 SHA-256 与原件比对通过。";},()=>backupStatus.Text="有效备份："+backup.Manifest.Id+" · "+backup.Manifest.Files.Count+" 个文件。现在可回安装页安装 / 更新。" );},true));p.Controls.Add(row);p.Controls.Add(backupStatus);
            p.Controls.Add(Theme.Label("恢复仅处理选定本地存档。恢复前完全退出 Ubisoft Connect，手动处理云同步冲突；不要通过关闭入侵选项来代替存档备份。"));
            var rr=Theme.Flow();rr.Controls.Add(Theme.Button("打开本地备份目录",(s,e)=>{Directory.CreateDirectory(Path.Combine(store.Root,"backups"));Open(Path.Combine(store.Root,"backups"));}));
            rr.Controls.Add(Theme.Button("选择并校验备份",(s,e)=>{using(var d=new OpenFileDialog{Filter="本工具备份清单|backup.json",InitialDirectory=Path.Combine(store.Root,"backups")})if(d.ShowDialog(this)==DialogResult.OK){string file=d.FileName;Work(()=>{backup=store.Verify(file);return "备份校验通过。";},()=>{save.Text=backup.Manifest.SourceDirectory;backupStatus.Text="已选择："+backup.Manifest.Id+" / "+backup.Manifest.Files.Count+" 文件。";});}}));
            rr.Controls.Add(Theme.Button("恢复所选备份",(s,e)=>{
                if(backup==null){MessageBox.Show("请先选择并校验一份备份。");return;}var b=backup;string dir=save.Text.Trim();
                if(!Confirm("将恢复 "+b.Manifest.Id+" 到其原始目录：\n"+dir+"\n当前存档会先做 before-restore 备份。多出的 .save/.sav 也会先备份再移除；其他文件保持不变。\n请确认已退出 Ubisoft Connect，并自行处理云同步。继续？"))return;
                string selectedGame=game.Text.Trim();
                Work(()=>{if(Directory.Exists(selectedGame))store.RevokeReceipts(selectedGame);store.Restore(b.ManifestPath,dir);return "存档恢复完成。请重新备份并安装，以更新插件回执。请在原游戏中核对进度。";},()=>{backup=null;backupStatus.Text="恢复后请重新备份。旧回执只是一份历史记录，不代表当前存档。";});
            }));p.Controls.Add(rr);return p;
        }
        Control Features() {
            var p=Theme.Flow(true);p.Controls.Add(Theme.Label("游戏内进度与参数，不再操作平台成就",true));
            p.Controls.Add(Theme.Label("无限 / 锁定与一次性增加均保留，分别控制。本轮增加原生候选引擎：数值回读、单项开关、单项增减、搜索、快捷键、模式隔离、失败恢复。未接通的项目在完整计划中逐条保留。"));
            p.Controls.Add(Theme.Button("打开独立参数控制面板",(s,e)=>{try{using(var f=new WD1Kit.Native.NativeForm(game.Text.Trim(),store,backup))f.ShowDialog(this);}catch(Exception ex){MessageBox.Show(ex.Message);}},true));
            p.Controls.Add(Theme.Label("原生面板先只读扫描，不需要 CE。启用捕获/写入必须有两小时内真实备份并明确单机确认。按项目源证据匹配，不使用猜测固定地址；所有游戏效果仍待你的机器实测。"));
            p.Controls.Add(Theme.Label("游戏内 Lua 菜单继续提供：上帝模式、弹药/专注补给、指定资源增加、普通技能点/XP 奖励、全武器/全服装/全物品白名单批次、车辆生成。不同接口不要同时维持同一数值。"));
            var row=Theme.Flow();row.Controls.Add(Theme.Button("打开完整功能计划",(s,e)=>Open(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"完整计划.html"))));row.Controls.Add(Theme.Button("查看本版操作说明",(s,e)=>Open(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"开始使用.html"))));p.Controls.Add(row);
            p.Controls.Add(Theme.Label("尚未接通的系统，不以假开关代替",true));
            p.Controls.Add(Theme.Label("游戏内主线/支线/调查/收集/在线合约的真实计数，全技能树前置、独立小游戏技能点、扑克1–4对象、饮酒光标和其他未绑定计时器，均保留在完整计划。未绑定项不会通过改同一个变量冒充四个玩家或全部模式。"));
            p.Controls.Add(Theme.Label("材料的“增加”与“无限”也分别保留。没有精确分类/拥有状态回读前，不把同时影响弹药和全部库存的公共补丁包装成独立材料开关。"));
            return p;
        }
        Control Reports() {
            var p=Theme.Flow(true);p.Controls.Add(Theme.Label("反馈只需要结果，不需要截图或完整存档",true));
            p.Controls.Add(Theme.Label("进入游戏后点 [REPORT]。退出游戏，在这里选择宿主日志；仅提取本插件受限格式的 [WD1KIT] 行。不会导出整份宿主日志、账号名、路径或存档内容。"));
            var row=Theme.Flow();row.Controls.Add(Theme.Button("提取插件日志片段",(s,e)=>{using(var d=new OpenFileDialog{Filter="宿主日志|*.log;*.txt|全部文件|*.*",InitialDirectory=game.Text})if(d.ShowDialog(this)==DialogResult.OK){try{pluginLines=ExtractLog(d.FileName);Note("提取了 "+pluginLines.Count+" 行安全格式的插件记录。");}catch(Exception ex){MessageBox.Show(ex.Message);}}}));
            row.Controls.Add(Theme.Button("导出脱敏测试报告",(s,e)=>Export(),true));p.Controls.Add(row);p.Controls.Add(log);
            p.Controls.Add(Theme.Label("请回报四件事：菜单是否出现；无敌开 / 关是否有效；技能点 +1 前后数字；OCP-11 / MP-9mm / SG-90 / Spec Ops Vector 重启后是否保留。原生面板可导出 WD1-Native-Probe.json；不导出内存转储。"));return p;
        }
        void Export(){using(var d=new SaveFileDialog{Filter="JSON 报告|*.json",FileName="WD1Kit-Feedback.json"})if(d.ShowDialog(this)==DialogResult.OK){try{
            if((!string.IsNullOrWhiteSpace(game.Text)&&Files.Under(d.FileName,game.Text))||(!string.IsNullOrWhiteSpace(save.Text)&&Files.Under(d.FileName,save.Text))||Files.Under(d.FileName,store.Root))throw new IOException("报告请另存到桌面 / 下载目录，不要覆盖游戏、存档或工具内部数据。");
            GameCheck g=null;try{g=Identity.Check(game.Text);}catch{}
            Files.Write(d.FileName,new{product="WD1KIT",version="0.3.3-alpha",utc=DateTime.UtcNow.ToString("o"),game_runtime_verified=false,observed_target_match=g!=null&&g.Matches,binary_hashes=g==null?null:g.Hashes,backup_selected=backup!=null,save_files_in_backup=backup==null?0:backup.Manifest.Files.Count,plugin_lines=pluginLines.ToArray()});Note("已导出脱敏报告。没有上传。");
        }catch(Exception ex){MessageBox.Show(ex.Message);}}}
        public static List<string> ExtractLog(string path) {
            var result=new List<string>();using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)){
                if(f.Length>4*1024*1024){f.Seek(-4*1024*1024,SeekOrigin.End);} using(var r=new StreamReader(f,Encoding.UTF8)){string line;while((line=r.ReadLine())!=null){int at=line.IndexOf("[WD1KIT] ",StringComparison.Ordinal);if(at<0)continue;line=line.Substring(at);if(Regex.IsMatch(line,@"^\[WD1KIT\] [A-Z_]+(?: [A-Za-z0-9_.,= -]{0,1800})?$")){result.Add(line);if(result.Count>1500)result.RemoveAt(0);}}}}
            return result;
        }
        void Choose(List<string> paths,string title,Action<string> picked) {
            if(paths.Count==0){MessageBox.Show("没有找到候选。请用“手动选择”找到实际游戏 / 存档文件夹；不会扫描整块硬盘。",title);return;}
            using(var f=new Form{Text=title,Width=850,Height=360,StartPosition=FormStartPosition.CenterParent}){var list=new ListBox{Dock=DockStyle.Fill,Font=new Font("Microsoft YaHei UI",10)};list.Items.AddRange(paths.Cast<object>().ToArray());var ok=new Button{Dock=DockStyle.Bottom,Height=40,Text="使用所选目录"};ok.Click+=(s,e)=>{if(list.SelectedItem!=null){picked(list.SelectedItem.ToString());f.Close();}};f.Controls.Add(list);f.Controls.Add(ok);f.ShowDialog(this);}
        }
        static List<string> SteamRoots(){var roots=new HashSet<string>(StringComparer.OrdinalIgnoreCase);try{var v=Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam","SteamPath",null) as string;if(v!=null)roots.Add(v);}catch{} foreach(var p in new[]{Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)})if(!string.IsNullOrWhiteSpace(p))roots.Add(Path.Combine(p,"Steam"));return roots.Where(Directory.Exists).ToList();}
        static List<string> FindGames(){var roots=new HashSet<string>(SteamRoots(),StringComparer.OrdinalIgnoreCase);foreach(var root in roots.ToArray()){string file=Path.Combine(root,"steamapps","libraryfolders.vdf");if(File.Exists(file))try{foreach(Match m in Regex.Matches(File.ReadAllText(file),"\\\"path\\\"\\s+\\\"([^\\\"]+)\\\""))roots.Add(m.Groups[1].Value.Replace("\\\\","\\"));}catch{}}return roots.Select(r=>Path.Combine(r,"steamapps","common","Watch_Dogs")).Concat(roots.Select(r=>Path.Combine(r,"steamapps","common","Watch Dogs"))).Where(p=>File.Exists(Path.Combine(p,"bin","Watch_Dogs.exe"))).Distinct(StringComparer.OrdinalIgnoreCase).ToList();}
        List<string> FindSaves(){var roots=new HashSet<string>(StringComparer.OrdinalIgnoreCase);foreach(var hive in new[]{"HKEY_LOCAL_MACHINE","HKEY_CURRENT_USER"})foreach(var key in new[]{@"\SOFTWARE\Ubisoft\Launcher",@"\SOFTWARE\WOW6432Node\Ubisoft\Launcher"})try{var p=Registry.GetValue(hive+key,"InstallDir",null) as string;if(!string.IsNullOrWhiteSpace(p))roots.Add(Path.Combine(p,"savegames"));}catch{}
            foreach(var p in new[]{Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)})if(!string.IsNullOrWhiteSpace(p))roots.Add(Path.Combine(p,"Ubisoft","Ubisoft Game Launcher","savegames"));
            var candidates=new List<string>();foreach(var r in roots)try{if(!Directory.Exists(r))continue;foreach(var user in Directory.GetDirectories(r))foreach(var id in new[]{"541","274"}){var d=Path.Combine(user,id);if(Directory.Exists(d)&&store.SaveFiles(d).Count>0)candidates.Add(d);}}catch{}return candidates.Distinct(StringComparer.OrdinalIgnoreCase).ToList();}
    }
}
