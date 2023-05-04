#include "geothermmainwindow.h"
#include "./ui_geothermmainwindow.h"
#include "./aboutdialog.h"
#include "QMessageBox"
#include "QFileDialog"
#include "embedding.h"
#include <iostream>

using namespace std;

bool compModuleLoaded = false;
QString appRoot = "/home/eugeneai/projects/code/dymsh";


GeothermMainWindow::GeothermMainWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::GeothermMainWindow)
{
    ui->setupUi(this);
    csvModel = new QCSVModel();
    // ui->csvView->setModel(csvModel);
}

void GeothermMainWindow::actionAbout() {
    AboutDialog a ;
    a.exec();
}

GeothermMainWindow::~GeothermMainWindow()
{
    delete csvModel;
    delete ui;
}

void GeothermMainWindow::on_pushButton_2_clicked()
{
    QString csvFileName = ui->dataFileName->text();
    if (csvFileName=="") {
        QMessageBox::information(this, "No file were chosen",
                                 QString("File name, You have chosen appears to be '%1'").arg(csvFileName));
        return;
    }
    if (loadCompModule()) {
        jl_value_t *ret = handleEval(QString("userDF=userLoadCSV(\"%1\")").arg(csvFileName));
        if (ret != nullptr) {
            csvModel->setDataFrame(ret);
            ui->csvView->setModel(csvModel);
        }
    }
}

void GeothermMainWindow::on_pushButton_clicked()
{
    // QMessageBox::information(this, "Clicked", "Button Clicked");
    QString csvFileName = QFileDialog::getOpenFileName(this, "Choose a CSV file of measurements",
                                                       QString("%1/data").arg(appRoot),
                                                       tr("CSV files (*.csv)"));
    ui->dataFileName->setText(csvFileName);
    on_pushButton_2_clicked();
}

// -----------------------------------------------------------

QModelIndex QCSVModel::index(int row, int column,
                             const QModelIndex &parent) const {
    Q_UNUSED(parent);
    return createIndex(row,column,nullptr);
}

QModelIndex QCSVModel::parent(const QModelIndex &index) const {
    return createIndex(-1,-1);
}

QVariant QCSVModel::data(const QModelIndex &index, int role) const {
    if (! index.isValid()) return QVariant();
    if (role == Qt::DisplayRole && dataFrame != nullptr) {
        int row = index.row();
        int col = index.column();
        QString cmd("string(userDF[%1,%2])");
        QString ncmd = cmd.arg(row+1).arg(col+1); // Long live, Julia!
        jl_value_t * ret = handleEval(ncmd);
        if (ret != nullptr) {
            return QString(jl_string_ptr(ret));
        } else {
            return QString("cannot show '%1'").arg(ncmd);
        }
    } else {
        return QVariant();
    }
}

QVariant QCSVModel::headerData(int section, Qt::Orientation orientation, int role) const {
    if (role != Qt::DisplayRole)
        return QVariant();

    if (orientation == Qt::Horizontal) {
        jl_value_t * ret = handleEval(QString("names(userDF)[%1]").arg(section+1));
        if (ret != nullptr) {
            QString name(jl_string_ptr(ret));
            QString mname = name.replace("_",", ");
            return mname;
        }
        /*
        if (section == 0) return "D,km";
        if (section == 1) return "P,mPa";
        if (section == 2) return "T,C";
        if (section == 3) return "T,K";
        */

        return QString("Column %1").arg(section);
    } else
        return QString("%1").arg(section+1);
}

jl_value_t * QCSVModel::setDataFrame(jl_value_t * df) {
    beginResetModel();
    dataFrame = df;
    endResetModel();
    return df;
}

int QCSVModel::columnCount(const QModelIndex &parent) const {
    Q_UNUSED(parent);
    if (dataFrame != nullptr) {
        jl_value_t * ret = handleEval("size(userDF,2)");
        return jl_unbox_int64(ret);
    } else return 10;
}
int QCSVModel::rowCount (const QModelIndex &parent) const {
    Q_UNUSED(parent);
    if (dataFrame != nullptr) {
        jl_value_t * ret = handleEval("size(userDF,1)");
        return jl_unbox_int64(ret);
    } else return 1;
}


// --------------------------------------------------------------

jl_value_t * handleEval(QString cmd) {
    jl_value_t * ret = nullptr;
    if (! compModuleLoaded) {
        if (!loadCompModule ())
            return ret;
    }
    ret = handle_eval_string(cmd.toStdString().c_str());
    if (ret != nullptr) {
        jl_call1(jl_get_function(jl_base_module, "show"), ret);
    } else {
        cout << "Julia command evaluation failed.\n";
    }
    cout.flush();
    return ret;
}

bool loadCompModule() {
    if (compModuleLoaded) {
        return true;
        cout << "Julia runtaime have been already loaded" << endl;
    }
    QString incString = QString("include(\"%1/computegterm.jl\")").arg(appRoot);
        if (handle_eval_string(incString.toStdString().c_str())!=nullptr) {
        cout << "Julia runtime successfully loaded.\n";
        compModuleLoaded = true;
    } else {
        cout << "Julia runtime loading failed.\n";
        compModuleLoaded = false;
    }
    cout.flush();
    return compModuleLoaded;
}



void GeothermMainWindow::on_calcPushButton_clicked()
{
    if (! csvModel->isValid()) {
        QMessageBox::critical(this,
                              "You did not load data!",
                              "In order to proceed with a compresesive computations, one must load an input deta. Proceeding to the page..");
        ui->views->setCurrentIndex(0);
    } else {

    }
}


void GeothermMainWindow::on_pushButton_3_clicked()
{
    if(! checkInitialData()) {
        QMessageBox::critical(this,
                              "Initial data is wrong",
                              "Check syntax of all the expressions. Hints are available (mouse hover for 5 seconds).");
    } else {
        QMessageBox::information(this,
                                 "The initial data syntax are ok!", "Now You can safely press 'Calculate' button!");
    }
}

QString GeothermMainWindow::constructInitialExpr() {
 // QString expr("GTInit(q0, 16, [16,23,39,300], 225, 0.1, 0.74, [0,0.4,0.4,0.02], 3, opt)");
    QString exprtmpl("GTInit(%1, %2, %3, %4, %5, %6, %7, %8, %9)");
    QString optCh;
    if (ui->opt->checkState()==Qt::Checked) {
        optCh="true";
    } else {
        optCh="false";
    }
    QString expr = exprtmpl
                       .arg(ui->q0->text()) //1
                       .arg(ui->D->text()) //2
                       .arg(ui->Zbot->text()) //3
                       .arg(ui->Zmax->text()) //4
                       .arg(ui->Dz->text()) //5
                       .arg(ui->P->text()) //6
                       .arg(ui->H->text()) //7
                       .arg(ui->iref->text()) //8
                       .arg(optCh);//9
    return expr;
}

bool GeothermMainWindow::checkInitialData() {
    QString expr = constructInitialExpr();
    jl_value_t * ret = handleEval(expr);
    return ret != nullptr;
}

