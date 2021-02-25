## 该脚本是为了能够更加完善的备份软件数据而创作的

如果出现任何问题，请详细说明，并携带你的错误 log

## 使用

#### 推荐的工具: MT管理器

1. 解压缩到任意目录 点击【appname.sh】并勾选root执行脚本 等待提示结束

   ![image-20210225011858607](https://github.com/chenaidairong/backup_script/blob/master/picture/image-20210225011858607.png)

2. 当前目录下会生成一个Apkname.txt, 这就是你要备份的软件列表, 你可以把你不需要备份的软件那一行前加上"#", 脚本就会自动跳过它了

   ![image-20210225012501486](https://github.com/chenaidairong/backup_script/blob/master/picture/image-20210225012501486.png)

3. 点击【backup.sh】并勾选root执行 等待备份结束

4. 会在当前目录看到多一个Backup资料夹里面都是你的软件备份吧这个资料夹整个备份起来刷好机直接在里面找到还原备份.sh即可恢复，同样道理里面有个name.txt 一样跟第二步骤操作一样不需要还原的删除

   #### 备注 ：一定要使用root权限执行脚本 ！！！！！！

   ![image-20210225012600790](https://github.com/chenaidairong/backup_script/blob/master/picture/image-20210225012600790.png)

   ## 问答：

5. 批量备份大量提示失败怎么办？
   答：退出脚本 删除Backup资料夹在备份一次

6. 批量恢复大量提示失败怎么办？
   答：退出脚本 在执行一次就好 不要删除资料夹
   如果还是错误截图脚本执行画面给我 我帮你排除错误

7. QQ WX能不能完美备份&恢复数据
   答：不能保证 有的人说不能有的可以 我自己测试QQ可以 所以备份会有提示 如果可以 用你信赖的备份软件针对QQ WX在备份一次以防万一丢失重要聊天数据

8. 某些APP备份很久 像是王者 pubg 原神 wx QQ备份为什么很久？
   答：因为连同软件数据包都给你备份了 原神数据包9gb+当然久到裂开了 恢复同理 还要解压缩数据包

   ### 上条的好处是：

   在更换系统之后，原有的数据全部保留，无需重新登陆

   

[作者酷安地址](http://www.coolapk.com/u/2277637)


![](https://avatars.githubusercontent.com/u/62833322?s=460&u=e349b67f15611011b1fee60102930f5df66e6d6e&v=4)


