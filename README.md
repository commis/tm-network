# 代码下载与编译

编译好可执行文件：
    
    ethermint
    tendermint

# 运行脚本启动网络

cd $GOPATH/src/github.com/commis/tm-network

make [down|upold|upnew|addold|addnew|start|del]

`说明:`

    参数介绍:
        up[old|new]：   启动初始化网络节点，支持新老版本
        down：          删除网络节点，所有节点容器都会被删除掉
        add[old|new]：  新增网络节点，支持一次添加多个normal节点，支持恢复一个损坏的共识节点，支持新老版本
        start：         启动新增加的网络节点（或者恢复的共识节点）
        del：           新增的普通节点可以直接删除掉，如果是恢复的共识节点，执行还命令后也会被删除，请注意
    
    网络节点配置文件，可以根据需要修改：
        $GOPATH/src/github.com/commis/tm-network/config/env.json
        
        文件配置解释：
            {
                "system":"ubuntu:16.04",    //监控节点镜像的操作系统
                "localhost":"192.168.56.4", //本地IP地址，脚本判断是否本机使用
                "user": { "name":"root", "passwd":"Energy@123" }, //分布式节点部署使用的用户名和密码
                "datapath":"/home/share/chaindata", //节点数据目录路径
                "setup": {
                    "node": {
                        "init": [
                            /*网络初始启动节点，type为类型：1为共识节点，0为普通节点*/
                            "peer1=192.168.56.4,type=1",
                            "peer2=192.168.56.4,type=1",
                            "peer3=192.168.56.4,type=1",
                            "peer4=192.168.56.4,type=1"
                        ],
                        "add": {
                            "from": { "node":"peer1", "data":"peer5" }, //恢复损坏的节点使用
                            "host": [
                                "peer6=192.168.56.4,type=1",
                                "peer7=192.168.56.4,type=0"
                            ]
                        }
                    },
                    "port": [
                        /*不同版本使用的端口*/
                        { "version":"0.18.0", "ports":"8545:8545 46656:46656 47767:45567 48868:45568", "debug":0, "p2ptm":0 },
                        { "version":"0.23.1", "ports":"8545:8545 46656:26656 47757:26657 48858:26658", "debug":0, "p2ptm":1 }
                    ]
                }
            }
            
    监控节点说明：
    	监控节点为开发测试使用。根据本机需要修改监控节点的IP地址，配置文件为jar包的application.yml文件。
    	
    	如果不需要启动监控节点，可以修改Makefile文件：
    	upold:
    	    @cd script && ./network_setup.sh -t up -v 0.18.0
    	upnew:
            @cd script && ./network_setup.sh -t up -v 0.23.1
    	    
    	down:
    	    @cd script && ./network_setup.sh -t down
   	    


