// Original WD1 in-process binding plans. Numeric instruction facts are attributed in docs.
using System;
using System.Collections.Generic;
using System.Linq;
namespace WD1Kit.Native {
 public class Site {
  public string Id,Pattern,Original,CaptureRegister; public int Offset; public bool Historic;
  public byte[] Expected {get{return Hex(Original);}}
  public static byte[] Hex(string x){return x.Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries).Select(s=>Convert.ToByte(s,16)).ToArray();}
 }
 public class Option {
  public string Id,Name,Group,Scope,Kind,Site,Note; public int Offset; public double Value,Min,Max; public bool Persistent;
 }
 public static class Contracts {
  public static readonly Site[] Sites={
   new Site{Id="resources",Pattern="8B 84 81 9C 00 00 00",Original="8B 84 81 9C 00 00 00",CaptureRegister="rcx"},
   new Site{Id="battery",Pattern="F3 0F 58 89 EC 00 00 00 0F",Original="F3 0F 58 89 EC 00 00 00",CaptureRegister="rcx"},
   new Site{Id="car",Pattern="41 0F 2F B6 D8 00 00 00",Original="41 0F 2F B6 D8 00 00 00",CaptureRegister="r14"},
   new Site{Id="spider",Pattern="F3 0F 10 83 08 10 00 00",Original="F3 0F 10 83 08 10 00 00",CaptureRegister="rbx"},
   new Site{Id="reputation",Pattern="F3 8B 42 10 48 83 C4 20",Offset=1,Original="8B 42 10 48 83 C4 20",CaptureRegister="rdx"},
   new Site{Id="police",Pattern="8B 48 50 49 8B 45 00",Original="8B 48 50 49 8B 45 00",CaptureRegister="rax"},
   new Site{Id="wanted",Pattern="0F B7 42 0C 48 83 C4 20",Original="0F B7 42 0C 48 83 C4 20",CaptureRegister="rdx"},
   new Site{Id="trip",Pattern="73 28 48 8B 03 F3 0F 10 73 0C",Offset=5,Original="F3 0F 10 73 0C",CaptureRegister="rbx"},
   new Site{Id="inventory_decrement",Pattern="2B C6 89 42 0C B0 01 EB",Original="2B C6",Historic=true},
   new Site{Id="reload",Pattern="FF 8F 98 00 00 00",Original="FF 8F 98 00 00 00"},
   new Site{Id="hacking_timer",Pattern="F3 0F 11 81 B4 00 00 00 48",Original="F3 0F 11 81 B4 00 00 00"},
   new Site{Id="stealth",Pattern="48 83 EC 28 F3 0F 10 51 08",Original="48 83 EC 28"},
   new Site{Id="drink_a",Pattern="18 F3 0F 59 C2 F3 0F 5C C8 0F 2F",Offset=5,Original="F3 0F 5C C8",Historic=true},
   new Site{Id="drink_b",Pattern="F3 0F 11 06 ?? ?? ?? ?? ?? 4C 8D 87 90 05 00 00",Original="F3 0F 11 06",Historic=true}
  };
  public static readonly Option[] Options={
   new Option{Id="money_floor",Name="无限金钱（最低余额）",Group="金钱 / 成长",Scope="freeroam",Kind="floor_i32",Site="resources",Offset=0x9c,Value=1000000,Min=0,Max=2000000000,Persistent=true},
   new Option{Id="skill_floor",Name="本体 / DLC 普通技能点最低值",Group="金钱 / 成长",Scope="freeroam",Kind="floor_i32",Site="resources",Offset=0xa0,Value=99,Min=0,Max=100000,Persistent=true,Note="不是蜘蛛坦克 / 疯狂 / 孤独技能树；这些独立记录尚未确定。"},
   new Option{Id="cash_add",Name="增加金钱",Group="金钱 / 成长",Scope="freeroam",Kind="add_i32",Site="resources",Offset=0x9c,Value=5000,Min=0,Max=2000000000,Persistent=true},
   new Option{Id="skill_add",Name="增加普通技能点",Group="金钱 / 成长",Scope="freeroam",Kind="add_i32",Site="resources",Offset=0xa0,Value=1,Min=0,Max=100000,Persistent=true},
   new Option{Id="xp_add",Name="增加普通经验",Group="金钱 / 成长",Scope="freeroam",Kind="add_i32",Site="resources",Offset=0xa8,Value=1000,Min=0,Max=2000000000,Persistent=true},
   new Option{Id="battery_full",Name="无限电池（补到当前容量）",Group="玩家 / 资源",Scope="freeroam",Kind="capacity_f32",Site="battery",Offset=0xec,Value=0xe8,Min=0,Max=100000},
   new Option{Id="car_health",Name="载具生命锁定",Group="载具",Scope="vehicle",Kind="floor_f32",Site="car",Offset=0xd8,Value=150,Min=0,Max=10000,Note="锁定当前稳定捕获的对象。不能据此证明仅作用玩家车辆；离车前先关闭。"},
   new Option{Id="spider_energy",Name="蜘蛛坦克无限能量",Group="数字之旅",Scope="spider",Kind="floor_f32",Site="spider",Offset=0x1008,Value=100,Min=0,Max=10000},
   new Option{Id="rep_good",Name="好声誉（锁定 +600）",Group="声誉 / 警察",Scope="freeroam",Kind="set_i32",Site="reputation",Offset=0x10,Value=600,Min=-600,Max=600,Persistent=true},
   new Option{Id="rep_bad",Name="坏名声（锁定 -600）",Group="声誉 / 警察",Scope="freeroam",Kind="set_i32",Site="reputation",Offset=0x10,Value=-600,Min=-600,Max=600,Persistent=true},
   new Option{Id="rep_up",Name="声誉增加",Group="声誉 / 警察",Scope="freeroam",Kind="add_i32",Site="reputation",Offset=0x10,Value=50,Min=-600,Max=600,Persistent=true},
   new Option{Id="rep_down",Name="声誉减少",Group="声誉 / 警察",Scope="freeroam",Kind="add_i32",Site="reputation",Offset=0x10,Value=-50,Min=-600,Max=600,Persistent=true},
   new Option{Id="police_detection",Name="无警方侦测",Group="声誉 / 警察",Scope="freeroam",Kind="set_i32",Site="police",Offset=0x50,Value=0,Min=0,Max=1000000,Note="与清除通缉分开；报警 / 剧情强制发现不保证屏蔽。"},
   new Option{Id="heat_clear",Name="消除当前通缉",Group="声誉 / 警察",Scope="freeroam",Kind="once_u16",Site="wanted",Offset=0x0c,Value=0,Min=0,Max=100},
   new Option{Id="heat_hold",Name="锁定无通缉",Group="声誉 / 警察",Scope="freeroam",Kind="set_u16",Site="wanted",Offset=0x0c,Value=0,Min=0,Max=100},
   new Option{Id="heat_up",Name="增加通缉热度",Group="声誉 / 警察",Scope="freeroam",Kind="add_u16",Site="wanted",Offset=0x0c,Value=10,Min=0,Max=100},
   new Option{Id="heat_down",Name="减少通缉热度",Group="声誉 / 警察",Scope="freeroam",Kind="add_u16",Site="wanted",Offset=0x0c,Value=-10,Min=0,Max=100},
   new Option{Id="inventory_infinite",Name="无限库存资源（材料 / 道具 / 备弹）",Group="材料 / 资源",Scope="freeroam",Kind="patch",Site="inventory_decrement",Persistent=true,Note="公共库存扣减保护，包含备弹；不是仅材料专用。与增加资源完全独立。旧签名须唯一匹配，当前槽位弹匣仍由独立弹药功能控制。"},
   new Option{Id="no_reload",Name="无需换弹",Group="玩家 / 资源",Scope="freeroam",Kind="patch",Site="reload",Note="停止扣减弹匣的候选代码路径；NPC 波及尚未实测排除。"},
   new Option{Id="stealth",Name="潜行 / 无探查（任务路径）",Group="声誉 / 警察",Scope="freeroam",Kind="return_zero",Site="stealth",Note="不是全局物理隐身；剧情强制事件另行验收。"},
   new Option{Id="hack_timer",Name="无限黑客计时器",Group="计时器",Scope="hacking",Kind="patch",Site="hacking_timer"},
   new Option{Id="drink_timer",Name="冻结饮酒游戏计时器",Group="计时器",Scope="drinking",Kind="multi_patch",Site="drink_a,drink_b",Note="含两个独立计时路径；旧版签名，须两处均唯一且原字节匹配。不是冻结鼠标。"},
   new Option{Id="spider_timer",Name="蜘蛛坦克：冻结当前计时",Group="计时器",Scope="spider",Kind="freeze_f32",Site="trip",Offset=0x0c,Min=0,Max=86400,Note="共享数字之旅计时器候选；活动类型由你选择，不是自动识别。对象变化即停止。"},
   new Option{Id="madness_timer",Name="疯狂：冻结当前计时",Group="计时器",Scope="madness",Kind="freeze_f32",Site="trip",Offset=0x0c,Min=0,Max=86400,Note="与蜘蛛计时独立控制但共用一个解析器；切换活动会先停全部。映射待实测。"}
  };
  public static List<int> Matches(byte[] image,string pattern){
   var p=pattern.Split(new[] { ' ' }, StringSplitOptions.None);var needle=p.Select(x=>x=="??"?(int)-1:Convert.ToByte(x,16)).ToArray();var list=new List<int>();int first=Array.FindIndex(needle,x=>x>=0);
   for(int i=0;i<=image.Length-p.Length;i++){
    if(first>=0&&image[i+first]!=needle[first])continue;
    bool hit=true;for(int j=0;j<p.Length;j++)if(needle[j]>=0&&image[i+j]!=needle[j]){hit=false;break;}
    if(hit){list.Add(i);if(list.Count>=64)break;}
   }return list;
  }
  public static byte[] Jump(long from,long to,int length){
   long delta=to-from-5;if(length<5||delta<int.MinValue||delta>int.MaxValue)throw new InvalidOperationException("跳转距离/长度不支持。");
   var b=Enumerable.Repeat((byte)0x90,length).ToArray();b[0]=0xe9;Buffer.BlockCopy(BitConverter.GetBytes((int)delta),0,b,1,4);return b;
  }
  public static byte[] CaptureStub(string register,long storage,long code,long back,byte[] displaced){
   var bytes=new List<byte>{0x9c,0x41,0x53,0x49,0xbb};bytes.AddRange(BitConverter.GetBytes(storage));
   var map=new Dictionary<string,byte[]>{{"rcx",new byte[]{0x49,0x89,0x0b}},{"rdx",new byte[]{0x49,0x89,0x13}},{"rbx",new byte[]{0x49,0x89,0x1b}},{"rax",new byte[]{0x49,0x89,0x03}},{"r14",new byte[]{0x4d,0x89,0x33}}};
   if(!map.ContainsKey(register))throw new InvalidOperationException("未验证的捕获寄存器。");
   bytes.AddRange(map[register]);bytes.AddRange(new byte[]{0x49,0xff,0x43,0x08});bytes.Add(0x41);bytes.Add(0x5b);bytes.Add(0x9d);
   // None of the admitted displaced instructions uses RIP-relative addressing or branches.
   bytes.AddRange(displaced);bytes.AddRange(Jump(code+bytes.Count,back,5));return bytes.ToArray();
  }
 }
}
