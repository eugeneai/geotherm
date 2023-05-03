#include "geothermmainwindow.h"
#include "./ui_geothermmainwindow.h"
#include "./aboutdialog.h"

GeothermMainWindow::GeothermMainWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::GeothermMainWindow)
{
    ui->setupUi(this);
}

void GeothermMainWindow::actionAbout() {
    AboutDialog a ;
    a.exec();
}

GeothermMainWindow::~GeothermMainWindow()
{
    delete ui;
}

